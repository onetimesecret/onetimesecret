# lib/onetime/services/zset_indexer.rb
#
# frozen_string_literal: true

#
# ZsetIndexer — populate a sorted set from Familia v1 hash fields without
# per-key round trips.
#
# == Design note
#
# === Problem
# Naive approach to building a sorted set ordered by a hash field value:
#   SCAN match=`prefix:*:object`  →  N HGET key field  →  N ZADD
# Two network round trips per key. At 273k customers and ~1100 cmd/s that's
# ~9 minutes.
#
# === Solution
# One EVALSHA per SCAN cursor batch (default 500 keys). The Lua script does
# `HGET` for each key in KEYS and returns aligned [score_or_nil, fallback_or_nil]
# pairs. Ruby applies the missing-field policy and emits a single pipelined
# ZADD batch. Round-trip arithmetic for N=273k, batch=500:
#   Cursor batches ≈ N/500 = 546
#   RT per batch:  2  (EVALSHA + pipelined ZADD block)
#   Total RT:     ~1100  vs  ~546k naive  →  ~500× reduction
#   Wall time:    seconds at LAN, 10–60s at WAN (vs ~9 min naive)
#
# === API
#   indexer = ZsetIndexer.new(
#     redis_url:       'redis://localhost:6379/6',
#     model_prefix:    'customer',
#     field_name:      'updated',
#     output_zset_key: 'ots:migration:customer:by_updated',
#   )
#   result = indexer.run  # dry-run by default
#   result = indexer.run(execute: true)
#
# Constructor options:
#   redis_url:        String   Redis URL including DB number (required)
#   model_prefix:     String   e.g. "customer", "customdomain" (required)
#   field_name:       String   Hash field to use as score (required)
#   output_zset_key:  String   Destination sorted set key (required)
#   fallback_field:   String   Secondary field to try when primary is missing
#   on_missing:       Symbol   :skip (default), :default, :fallback_field
#   default_score:    Numeric  Score to use when on_missing: :default
#   batch_size:       Integer  Keys per Lua call (default: 500)
#   scan_count:       Integer  SCAN COUNT hint (default: 1000)
#   clear_first:      Boolean  DEL output_zset_key before indexing (default: false)
#   progress_every:   Integer  Print progress line every N keys (default: 10_000)
#
# === Missing-field policy
#   :skip           Drop the key. Output zset will have fewer members than
#                   the source. Good when missing means "never updated" and
#                   those records should simply never be enqueued.
#   :default        Use default_score. Every key lands in the output zset,
#                   old unknowns cluster at the configured score.
#   :fallback_field Use fallback_field value (Lua fetches both in one pass).
#                   If fallback is also missing, falls through to :skip.
#
# === v1/v2 field format tolerance
# Familia v1 stores integers as bare strings: `"1735689600"`.
# Familia v2 JSON-encodes scalars: `"\"1735689600\""`.
# parse_score handles both: strip surrounding double-quotes then Float().
# nil/empty → nil (triggers missing-field policy).
#
# === Idempotency and resumability
# ZADD with the same score for the same member is a no-op on the sorted set.
# Re-running over an already-populated output zset converges to the same
# state. A mid-run crash leaves a partial zset — re-run to complete.
# Use clear_first: true to get a clean slate (e.g. schema changed, want
# fresh ordering). clear_first deletes the output zset before the first SCAN
# cursor completes, so it is not atomic with respect to the scan. For large
# datasets this is acceptable since the scan/zadd loop itself is not atomic.
#
# === Sharp edges
# - output_zset_key must not match the SCAN glob (self-feedback loop).
#   A key like "customer:ots:migration:customer:by_updated:object" is unlikely
#   but the guard is on the caller.
# - Cluster mode unsupported: KEYS[] in EVAL span multiple hash slots; the
#   output zset is likely on a different slot than most source keys. Run
#   against a single-node or sentinel setup.
# - `prefix:*:object` also matches multi-segment identifiers such as
#   `customer:a:b:object`. In v1 customer keys are email-keyed
#   (`customer:user@example.com:object`) which may contain `:` — the glob
#   still matches correctly since `*` is greedy.
# - Lua memory: 1000 HGET results with large values (multi-KB hashes) can
#   approach the Lua memory limit. Default batch_size=500 is conservative.
#   Reduce further for models with very large hash payloads.

require 'redis'
require 'uri'

module Onetime
  module Services
    class ZsetIndexer
      # Lua script: given N keys, HGET primary field + optional fallback field.
      # Returns array of [primary_val_or_false, fallback_val_or_false] per key.
      # false (not nil) because Redis Lua returns nil as false in arrays.
      LUA_SCRIPT = <<~LUA
        local field   = ARGV[1]
        local fb      = ARGV[2]  -- empty string means no fallback
        local results = {}
        for i = 1, #KEYS do
          local primary  = redis.call('HGET', KEYS[i], field)
          local fallback = false
          if fb ~= '' then
            fallback = redis.call('HGET', KEYS[i], fb)
          end
          results[i] = { primary, fallback }
        end
        return results
      LUA

      DEFAULT_BATCH_SIZE   = 500
      DEFAULT_SCAN_COUNT   = 1000
      DEFAULT_PROGRESS_AT  = 10_000

      attr_reader :stats

      def initialize(
        redis_url:,
        model_prefix:,
        field_name:,
        output_zset_key:,
        fallback_field:  nil,
        on_missing:      :skip,
        default_score:   0,
        batch_size:      DEFAULT_BATCH_SIZE,
        scan_count:      DEFAULT_SCAN_COUNT,
        clear_first:     false,
        progress_every:  DEFAULT_PROGRESS_AT
      )
        @redis_url       = redis_url
        @model_prefix    = model_prefix
        @field_name      = field_name
        @output_zset_key = output_zset_key
        @fallback_field  = fallback_field
        @on_missing      = on_missing
        @default_score   = default_score
        @batch_size      = batch_size
        @scan_count      = scan_count
        @clear_first     = clear_first
        @progress_every  = progress_every

        unless [:skip, :default, :fallback_field].include?(@on_missing)
          raise ArgumentError, "on_missing must be :skip, :default, or :fallback_field; got #{@on_missing.inspect}"
        end

        if @on_missing == :fallback_field && @fallback_field.nil?
          raise ArgumentError, 'fallback_field: must be set when on_missing: :fallback_field'
        end

        @stats = {
          scanned: 0,
          scored: 0,
          missing: 0,
          errors: [],
          start_at: nil,
          end_at: nil,
        }
      end

      def run(execute: false)
        @stats[:start_at] = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        redis = connect
        sha   = load_script(redis)

        unless execute
          $stdout.puts "DRY RUN: would index #{@model_prefix}:*:object by #{@field_name} into #{@output_zset_key}"
        end

        if execute && @clear_first
          redis.del(@output_zset_key)
          $stdout.puts "Cleared #{@output_zset_key}"
        end

        pattern = "#{@model_prefix}:*:object"
        cursor  = '0'

        loop do
          cursor, keys = redis.scan(cursor, match: pattern, count: @scan_count)
          process_batch(redis, sha, keys, execute: execute) unless keys.empty?
          break if cursor == '0'
        end

        @stats[:end_at] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        log_final

        @stats
      ensure
        redis&.close
      end

      private

      # Larger timeouts than 1s default — EVAL on 500-key batches over a large
      # dataset can exceed 1s, particularly when Redis is under load.
      def connect
        uri = URI.parse(@redis_url)
        Redis.new(
          url: uri.to_s,
          connect_timeout: 10,
          read_timeout: 30,
          write_timeout: 10,
          reconnect_attempts: [0.5, 1.0, 2.0],
        )
      rescue URI::InvalidURIError => ex
        raise ArgumentError, "Invalid redis_url: #{ex.message}"
      end

      def load_script(redis)
        redis.script(:load, LUA_SCRIPT)
      rescue Redis::CommandError => ex
        raise "Failed to load Lua script: #{ex.message}"
      end

      def process_batch(redis, sha, keys, execute:)
        fb_arg = @fallback_field.to_s  # empty string disables fallback in Lua

        # EVALSHA with NOSCRIPT fallback — script may be evicted from server cache.
        raw_results = evalsha_with_fallback(redis, sha, keys, fb_arg)

        zadd_pairs = []

        keys.each_with_index do |key, idx|
          primary_raw, fallback_raw = raw_results[idx]
          # Lua returns false for Redis nil; normalise to nil.
          primary_raw               = nil if primary_raw  == false
          fallback_raw              = nil if fallback_raw == false

          score = resolve_score(primary_raw, fallback_raw, key)
          next if score.nil?

          # ZADD expects [score, member]. Member is the full key — enqueuer
          # workers read it directly without reconstruction.
          zadd_pairs << score << key
        end

        @stats[:scanned] += keys.size

        if execute && !zadd_pairs.empty?
          # Pipelined ZADD in chunks to avoid oversized pipeline buffers.
          # Each pair is [score, member] so divide by 2 for member count.
          pair_count       = zadd_pairs.size / 2
          zadd_pairs.each_slice(@batch_size * 2) do |chunk|
            redis.pipelined(exception: false) do |pipe|
              # zadd accepts array of [score, member] pairs but the ruby redis
              # gem wants them as a flat list: score, member, score, member…
              chunk.each_slice(2) { |score, member| pipe.zadd(@output_zset_key, score, member) }
            end
          end
          @stats[:scored] += pair_count
        elsif !execute
          @stats[:scored] += zadd_pairs.size / 2
        end

        log_progress if should_log?(@stats[:scanned])
      rescue Redis::CommandError => ex
        @stats[:errors] << { batch_start: keys.first, error: ex.message }
      end

      def evalsha_with_fallback(redis, sha, keys, fb_arg)
        redis.evalsha(sha, keys: keys, argv: [@field_name, fb_arg])
      rescue Redis::CommandError => ex
        raise unless ex.message.start_with?('NOSCRIPT')

        # Script was evicted; re-load and retry once.
        sha_new = load_script(redis)
        redis.evalsha(sha_new, keys: keys, argv: [@field_name, fb_arg])
      end

      # Apply missing-field policy. Returns a Numeric score or nil (skip).
      def resolve_score(primary_raw, fallback_raw, _key)
        score = parse_score(primary_raw)
        return score unless score.nil?

        case @on_missing
        when :skip
          @stats[:missing] += 1
          nil
        when :default
          @stats[:missing] += 1
          @default_score
        when :fallback_field
          fb_score = parse_score(fallback_raw)
          if fb_score.nil?
            @stats[:missing] += 1
            nil
          else
            fb_score
          end
        end
      end

      # Parse a raw Redis string value as a numeric score.
      # Handles v1 bare integers ("1735689600") and v2 JSON-quoted integers
      # ("\"1735689600\""). Returns Integer or nil on unparseable input.
      def parse_score(raw)
        return nil if raw.nil? || raw.empty?

        # Strip surrounding JSON double-quotes if present (v2 format).
        clean = raw.strip
        clean = clean[1..-2] if clean.start_with?('"') && clean.end_with?('"')

        Float(clean).to_i
      rescue ArgumentError
        nil
      end

      def should_log?(count)
        count > 0 && (count % @progress_every).zero?
      end

      def log_progress
        elapsed  = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @stats[:start_at]
        rate     = elapsed > 0 ? (@stats[:scanned] / elapsed).round : 0
        $stdout.puts "#{@model_prefix} scored: #{@stats[:scored]} of #{@stats[:scanned]} scanned (#{rate}/s)"
        $stdout.flush
      end

      def log_final
        elapsed = @stats[:end_at] - @stats[:start_at]
        rate    = elapsed > 0 ? (@stats[:scanned] / elapsed).round : 0
        $stdout.puts "Done: #{@model_prefix} — scanned=#{@stats[:scanned]} scored=#{@stats[:scored]} " \
                     "missing=#{@stats[:missing]} errors=#{@stats[:errors].size} (#{rate}/s, #{elapsed.round(1)}s)"
      end
    end
  end
end
