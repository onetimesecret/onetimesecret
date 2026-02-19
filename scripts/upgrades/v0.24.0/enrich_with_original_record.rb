#!/usr/bin/env ruby
# frozen_string_literal: true

# Restores original v1 records as _original_* Redis keys for rollback/audit.
#
# Uses Redis RESTORE to place v1 dump binaries directly as sibling keys
# alongside v2 records, with a 30-day TTL for automatic cleanup.
#
# Two-phase approach:
#   Phase A — Build v1→v2 objid mapping from transformed JSONL
#   Phase B — Stream v1 dump JSONL and RESTORE each record to its target key
#
# Target key pattern:
#   {v2_prefix}:{objid}:_original_{suffix}
#
# Examples:
#   customer:abc-def-123:_original_object        (from customer:email@example.com:object)
#   custom_domain:abc-def-123:_original_object    (from customdomain:example.com:object)
#   custom_domain:abc-def-123:_original_brand     (from customdomain:example.com:brand)
#   receipt:abc-def-123:_original_object          (from metadata:xv4z6nh...:object)
#   secret:abc-def-123:_original_object           (from secret:abc123...:object)
#
# Usage:
#   ruby scripts/upgrades/v0.24.0/enrich_with_original_record.rb [OPTIONS]
#
# Options:
#   --input-dir=DIR    Input directory with dump/transformed files (default: data/upgrades/v0.24.0)
#   --redis-url=URL    Redis URL for RESTORE operations (env: VALKEY_URL or REDIS_URL)
#   --target-db=N      Target database number (default: 0)
#   --dry-run          Preview without writing to Redis
#   --help             Show this help
#
# Input:
#   data/upgrades/v0.24.0/{model}/{model}_dump.jsonl        (v1 dump — source of RESTORE binaries)
#   data/upgrades/v0.24.0/{model}/{model}_transformed.jsonl (v2 records — source of v1→v2 mapping)
#
# Output:
#   Redis keys with 30-day TTL: {v2_prefix}:{objid}:_original_{suffix}
#
# This script runs AFTER transform.rb scripts and load_keys.rb.

require 'json'
require 'base64'
require 'securerandom'
require 'redis'
require 'familia'
require 'uri'

DEFAULT_DATA_DIR = 'data/upgrades/v0.24.0'

class OriginalRecordRestorer
  TEMP_KEY_PREFIX = '_restore_mapping_tmp_'
  THIRTY_DAYS_MS = 30 * 24 * 60 * 60 * 1000 # 2_592_000_000

  # Model configurations
  #
  # v1_prefix:        Redis key prefix in v1 dump files
  # v2_prefix:        Redis key prefix in v2 (target for _original_* keys)
  # related_suffixes: Key suffixes to preserve from v1 dump
  # dir:              Subdirectory in data/upgrades/v0.24.0/
  # dump_file:        V1 dump JSONL filename
  # transformed_file: V2 transformed JSONL filename
  MODEL_CONFIG = {
    'customer' => {
      v1_prefix: 'customer',
      v2_prefix: 'customer',
      related_suffixes: %w[object],
      dir: 'customer',
      dump_file: 'customer_dump.jsonl',
      transformed_file: 'customer_transformed.jsonl',
    },
    'customdomain' => {
      v1_prefix: 'customdomain',
      v2_prefix: 'custom_domain',
      related_suffixes: %w[object brand logo icon],
      dir: 'customdomain',
      dump_file: 'customdomain_dump.jsonl',
      transformed_file: 'customdomain_transformed.jsonl',
    },
    'metadata' => {
      v1_prefix: 'metadata',
      v2_prefix: 'receipt',
      related_suffixes: %w[object],
      dir: 'metadata',
      dump_file: 'metadata_dump.jsonl',
      transformed_file: 'receipt_transformed.jsonl',
    },
    'secret' => {
      v1_prefix: 'secret',
      v2_prefix: 'secret',
      related_suffixes: %w[object],
      dir: 'secret',
      dump_file: 'secret_dump.jsonl',
      transformed_file: 'secret_transformed.jsonl',
    },
  }.freeze

  def initialize(input_dir:, redis_url:, target_db:, dry_run: false)
    @input_dir  = input_dir
    @redis_url  = redis_url
    @target_db  = target_db
    @dry_run    = dry_run
    @redis      = nil

    @stats = Hash.new do |h, k|
      h[k] = { mapped: 0, restored: 0, skipped: 0, not_found: 0, errors: [] }
    end
  end

  def run
    connect_redis unless @dry_run

    MODEL_CONFIG.each do |model, config|
      process_model(model, config)
    end

    print_summary
    @stats
  ensure
    @redis&.close
  end

  private

  def connect_redis
    uri      = URI.parse(@redis_url)
    uri.path = "/#{@target_db}"
    @redis   = Redis.new(url: uri.to_s)
    @redis.ping
  rescue Redis::CannotConnectError => ex
    warn "Failed to connect to Redis: #{ex.message}"
    warn 'Redis is required for RESTORE operations.'
    exit 1
  end

  def process_model(model, config)
    dump_file        = File.join(@input_dir, config[:dir], config[:dump_file])
    transformed_file = File.join(@input_dir, config[:dir], config[:transformed_file])

    unless File.exist?(dump_file)
      puts "Skipping #{model}: #{dump_file} not found"
      return
    end

    unless File.exist?(transformed_file)
      puts "Skipping #{model}: #{transformed_file} not found"
      return
    end

    puts "Processing #{model}..."

    if @dry_run
      dry_run_model(model, config, dump_file, transformed_file)
    else
      restore_model(model, config, dump_file, transformed_file)
    end
  end

  # ── Dry Run ──────────────────────────────────────────────

  def dry_run_model(model, config, dump_file, transformed_file)
    stats = @stats[model]

    # Count transformed :object records (potential mapping entries)
    File.foreach(transformed_file) do |line|
      record = JSON.parse(line.chomp, symbolize_names: true)
      stats[:mapped] += 1 if record[:key]&.end_with?(':object')
    rescue JSON::ParserError
      # Skip malformed lines
    end

    # Count v1 dump records by suffix
    suffix_counts = Hash.new(0)
    File.foreach(dump_file) do |line|
      record = JSON.parse(line.chomp, symbolize_names: true)
      next unless record[:key]

      suffix = extract_suffix(record[:key])
      if config[:related_suffixes].include?(suffix)
        suffix_counts[suffix] += 1
      else
        stats[:skipped] += 1
      end
    rescue JSON::ParserError
      # Skip malformed lines
    end

    puts "  Mapping entries (transformed :object records): #{stats[:mapped]}"
    suffix_counts.each do |suffix, count|
      puts "  Would restore #{count} :#{suffix} records → _original_#{suffix}"
    end
    puts "  Skipped (unrecognized suffix): #{stats[:skipped]}" if stats[:skipped] > 0
  end

  # ── Phase A: Build v1→v2 Mapping ────────────────────────

  def build_v1_to_v2_mapping(model, config, dump_file, transformed_file)
    # Try the enriched dump file first (customer/customdomain have objid at top-level)
    mapping = build_mapping_from_dump(dump_file)
    if mapping.any?
      puts "  Phase A: Built #{mapping.size} mappings from enriched dump"
      return mapping
    end

    # Fallback: extract v1_identifier from transformed JSONL via temp RESTORE
    mapping = build_mapping_from_transformed(config, transformed_file)
    puts "  Phase A: Built #{mapping.size} mappings from transformed JSONL"
    mapping
  end

  # Build mapping from enriched dump file (customer/customdomain have objid)
  def build_mapping_from_dump(dump_file)
    mapping = {}

    File.foreach(dump_file) do |line|
      record = JSON.parse(line.chomp, symbolize_names: true)
      next unless record[:key]&.end_with?(':object') && record[:objid]

      v1_prefix = strip_suffix(record[:key])
      mapping[v1_prefix] = record[:objid]
    rescue JSON::ParserError
      # Skip malformed lines
    end

    mapping
  end

  # Build mapping by RESTOREing transformed dumps to read v1_identifier
  def build_mapping_from_transformed(config, transformed_file)
    mapping = {}

    File.foreach(transformed_file) do |line|
      record = JSON.parse(line.chomp, symbolize_names: true)
      next unless record[:key]&.end_with?(':object')

      objid = record[:objid]
      next unless objid

      # RESTORE dump temporarily to read v1_identifier field
      v1_identifier = read_field_from_dump(record[:dump], 'v1_identifier')
      next unless v1_identifier

      # Deserialize JSON-encoded value from Familia v2 serialization
      v1_key = deserialize_v2_value(v1_identifier)
      next unless v1_key

      v1_prefix = strip_suffix(v1_key)
      mapping[v1_prefix] = objid
    rescue JSON::ParserError
      # Skip malformed lines
    end

    mapping
  end

  # ── Phase B: RESTORE v1 Dumps ───────────────────────────

  def restore_model(model, config, dump_file, transformed_file)
    stats = @stats[model]

    # Phase A: Build v1_prefix → v2_objid mapping
    mapping = build_v1_to_v2_mapping(model, config, dump_file, transformed_file)
    stats[:mapped] = mapping.size

    # Phase B: Stream v1 dump and RESTORE each record
    File.foreach(dump_file) do |line|
      record = JSON.parse(line.chomp, symbolize_names: true)
      next unless record[:key] && record[:dump]

      suffix = extract_suffix(record[:key])
      unless config[:related_suffixes].include?(suffix)
        stats[:skipped] += 1
        next
      end

      v1_prefix = strip_suffix(record[:key])
      objid     = mapping[v1_prefix]

      unless objid
        stats[:not_found] += 1
        next
      end

      # Compute v2 target key: {v2_prefix}:{objid}:_original_{suffix}
      target_key = "#{config[:v2_prefix]}:#{objid}:_original_#{suffix}"

      # Decode and RESTORE with 30-day TTL
      restore_to_target(target_key, record[:dump], stats)
    rescue JSON::ParserError => ex
      stats[:errors] << { error: ex.message }
    end

    puts "  Phase B: Restored #{stats[:restored]} keys (#{stats[:not_found]} not mapped, #{stats[:skipped]} skipped)"
    puts "  Errors: #{stats[:errors].size}" if stats[:errors].any?
  end

  def restore_to_target(target_key, dump_b64, stats)
    dump_data = Base64.strict_decode64(dump_b64)
    @redis.restore(target_key, THIRTY_DAYS_MS, dump_data, replace: true)
    stats[:restored] += 1
  rescue Redis::CommandError => ex
    stats[:errors] << { key: target_key, error: ex.message }
    warn "  Warning: Failed to restore #{target_key}: #{ex.message}"
  end

  # ── Helpers ─────────────────────────────────────────────

  # Read a single field from a dump binary via temp RESTORE + HGET
  def read_field_from_dump(dump_b64, field_name)
    temp_key  = "#{TEMP_KEY_PREFIX}#{SecureRandom.hex(8)}"
    dump_data = Base64.strict_decode64(dump_b64)

    @redis.restore(temp_key, 0, dump_data)
    @redis.hget(temp_key, field_name)
  rescue Redis::CommandError
    nil
  ensure
    @redis&.del(temp_key)
  end

  # Deserialize a Familia v2 JSON-encoded value back to Ruby
  def deserialize_v2_value(raw_value)
    return nil if raw_value.nil? || raw_value == 'null'
    return raw_value if raw_value.empty?

    Familia::JsonSerializer.parse(raw_value)
  rescue Familia::SerializerError
    raw_value
  end

  # Extract the suffix (last colon-separated segment) from a Redis key
  def extract_suffix(key)
    last_colon = key.rindex(':')
    return key unless last_colon

    key[(last_colon + 1)..]
  end

  # Strip the suffix from a Redis key, returning the prefix
  def strip_suffix(key)
    last_colon = key.rindex(':')
    return key unless last_colon

    key[0...last_colon]
  end

  # ── Summary ─────────────────────────────────────────────

  def print_summary
    puts "\n=== Original Record Restoration Summary ==="
    @stats.each do |model, stats|
      puts "#{model}:"
      puts "  Mapping entries:  #{stats[:mapped]}"
      puts "  Keys restored:    #{stats[:restored]}"
      puts "  Not mapped:       #{stats[:not_found]}" if stats[:not_found] > 0
      puts "  Skipped:          #{stats[:skipped]}" if stats[:skipped] > 0
      next unless stats[:errors].any?

      puts "  Errors:           #{stats[:errors].size}"
      stats[:errors].first(5).each do |err|
        puts "    #{err[:key] || 'unknown'}: #{err[:error]}"
      end
    end
  end
end

def parse_args(args)
  options = {
    input_dir: DEFAULT_DATA_DIR,
    redis_url: ENV['VALKEY_URL'] || ENV.fetch('REDIS_URL', nil),
    target_db: 0,
    dry_run: false,
  }

  args.each do |arg|
    case arg
    when /^--input-dir=(.+)$/
      options[:input_dir] = Regexp.last_match(1)
    when /^--redis-url=(.+)$/
      options[:redis_url] = Regexp.last_match(1)
    when /^--target-db=(\d+)$/
      options[:target_db] = Regexp.last_match(1).to_i
    when '--dry-run'
      options[:dry_run] = true
    when '--help', '-h'
      puts <<~HELP
        Usage: ruby scripts/upgrades/v0.24.0/enrich_with_original_record.rb [OPTIONS]

        Restores original v1 records as _original_* Redis keys with 30-day TTL.

        Options:
          --input-dir=DIR    Input directory (default: data/upgrades/v0.24.0)
          --redis-url=URL    Redis URL for RESTORE (env: VALKEY_URL or REDIS_URL)
          --target-db=N      Target database number (default: 0)
          --dry-run          Preview without writing to Redis
          --help             Show this help

        Input files:
          data/upgrades/v0.24.0/{model}/{model}_dump.jsonl        (v1 source binaries)
          data/upgrades/v0.24.0/{model}/{model}_transformed.jsonl (v2 mapping source)

        Output:
          Redis keys: {v2_prefix}:{objid}:_original_{suffix}
          TTL: 30 days (2,592,000,000 ms)

        Key mapping:
          customer:email@...:object      → customer:{objid}:_original_object
          customdomain:dom:object        → custom_domain:{objid}:_original_object
          customdomain:dom:brand         → custom_domain:{objid}:_original_brand
          customdomain:dom:logo          → custom_domain:{objid}:_original_logo
          customdomain:dom:icon          → custom_domain:{objid}:_original_icon
          metadata:key:object            → receipt:{objid}:_original_object
          secret:key:object              → secret:{objid}:_original_object

        This script runs AFTER transform.rb scripts and load_keys.rb.
      HELP
      exit 0
    else
      warn "Unknown option: #{arg}"
      exit 1
    end
  end

  options
end

if __FILE__ == $PROGRAM_NAME
  options = parse_args(ARGV)

  restorer = OriginalRecordRestorer.new(
    input_dir: options[:input_dir],
    redis_url: options[:redis_url],
    target_db: options[:target_db],
    dry_run: options[:dry_run],
  )

  restorer.run
end
