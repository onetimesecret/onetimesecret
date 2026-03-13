# lib/onetime/cli/customers/shared.rb
#
# frozen_string_literal: true

# Shared utilities for customer CLI commands (dates, purge).
# Provides timestamp parsing, Redis helpers, time constants,
# and cache management used across multiple customer subcommands.

module Onetime
  module CLI
    module Customers
      module Shared
        # Approximate durations for human-readable time thresholds.
        # Not calendar-precise (no leap years, 30-day months) but
        # sufficient for bucket boundaries and CLI duration parsing.
        SECONDS_IN_DAY   = 86_400
        SECONDS_IN_MONTH = 30 * SECONDS_IN_DAY
        SECONDS_IN_YEAR  = 365 * SECONDS_IN_DAY

        # Balance freshness vs Redis load; 30min avoids repeated full
        # SCANs while keeping data current enough for operational use.
        CACHE_TTL = 1800

        # SCAN cursor batch size; 200 keeps round-trips low without
        # blocking Redis for too long on each iteration.
        SCAN_COUNT = 200

        # Redis pipeline batch size for HMGET calls; 500 balances
        # memory overhead against round-trip count on large datasets.
        PIPELINE_BATCH = 500

        # -- Timestamp & field parsing -----------------------------------

        # Parse a raw Redis value as a numeric timestamp. Handles both
        # JSON-encoded strings (Familia v2) and bare floats (v1).
        def parse_ts(raw)
          return 0.0 if raw.nil? || raw.to_s.strip.empty?

          JSON.parse(raw).to_f
        rescue JSON::ParserError
          raw.to_f
        end

        # Parse a raw Redis value as a JSON field (string, number, etc).
        # Falls back to the raw string when the value is not valid JSON.
        def parse_json_field(raw)
          return nil if raw.nil? || raw.to_s.strip.empty?

          JSON.parse(raw)
        rescue JSON::ParserError
          raw.to_s
        end

        # -- Redis helpers -----------------------------------------------

        def redis_client_from_url(url)
          uri = URI.parse(url)
          db  = uri.path.to_s.sub('/', '').to_i

          Redis.new(
            host: uri.host,
            port: uri.port || 6379,
            db: db,
            password: uri.password,
            username: uri.user == '' ? nil : uri.user,
            timeout: 30,
            reconnect_attempts: 3,
          )
        end

        def redact_url(url)
          url.sub(%r{:[^:@/]+@}, ':***@')
        end

        def format_ttl(seconds)
          if seconds >= 60
            "#{seconds / 60}m #{seconds % 60}s"
          else
            "#{seconds}s"
          end
        end

        # -- Cache management --------------------------------------------

        # Check for existing cache and report status, or trigger a build.
        # +primary_key+: the cache key to check for existence/TTL.
        def ensure_cache(source_redis, cache_redis, primary_key:, **)
          if cache_redis.exists?(primary_key)
            ttl   = cache_redis.ttl(primary_key)
            count = cache_redis.zcard(primary_key)
            puts "Using cached data: #{count} records (expires in #{format_ttl(ttl)})"
            puts
            return
          end

          build_cache(source_redis, cache_redis)
        end

        # Set TTL on cache keys and print summary.
        # +skip_label+: describes what the skipped count represents
        #   (e.g., "no created date" or "without activity date").
        def finalize_cache(cache_redis, count, skipped, cache_keys:, skip_label: 'skipped')
          cache_keys.each do |key|
            cache_redis.expire(key, CACHE_TTL) if cache_redis.exists?(key)
          end

          puts "Cached #{count} records (#{skipped} #{skip_label})"
          puts 'Cache valid for 30 minutes (--refresh to rebuild)'
          puts
        end
      end
    end
  end
end
