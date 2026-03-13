# lib/onetime/cli/customers/shared.rb
#
# frozen_string_literal: true

# Shared utilities for customer CLI commands (dates, purge).
# Provides timestamp parsing, Redis helpers, and time constants
# used across multiple customer subcommands.

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
      end
    end
  end
end
