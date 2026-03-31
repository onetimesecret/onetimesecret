# lib/onetime/security/dns_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # DnsRateLimiter - Prevents excessive DNS verification attempts
    #
    # Tracks DNS verification requests per domain using Redis.
    # After MAX_VERIFICATIONS within the RATE_WINDOW, further verification
    # attempts are blocked until the window resets.
    #
    # This protects against:
    #   - Excessive DNS queries triggering provider rate limits
    #   - Abuse of the verification endpoint
    #   - Unnecessary load on DNS infrastructure
    #
    # Redis keys:
    #   - dns:ratelimit:{domain_id} - Counter of verification attempts (expires with RATE_WINDOW)
    #
    # Usage:
    #   include Onetime::Security::DnsRateLimiter
    #
    #   # Before DNS verification:
    #   check_dns_rate_limit!(domain_id)
    #
    #   # Get current rate limit status:
    #   status = dns_rate_limit_status(domain_id)
    #   status[:remaining]  # => 8
    #   status[:reset_in]   # => 2400 (seconds)
    #
    module DnsRateLimiter
      # Maximum verification attempts allowed per domain
      MAX_VERIFICATIONS = 10

      # Window in seconds for counting verifications (1 hour)
      RATE_WINDOW = 3600

      # Lua script to atomically check and increment verification count.
      # Returns: [current_count, ttl, was_new_key]
      # - current_count: count after increment
      # - ttl: seconds until key expires (-1 if key was just created)
      # - was_new_key: 1 if this was the first request in window, 0 otherwise
      #
      # NOTE: redis.call('EVAL', ...) executes server-side Lua, not Ruby eval.
      # This is the standard Redis atomic scripting pattern.
      CHECK_AND_INCREMENT_SCRIPT = <<~LUA
        local key = KEYS[1]
        local rate_window = tonumber(ARGV[1])
        local max_verifications = tonumber(ARGV[2])

        local current_count = redis.call('GET', key)
        local was_new_key = 0
        local ttl = -1

        if current_count then
          current_count = tonumber(current_count)
          ttl = redis.call('TTL', key)

          -- Check if limit would be exceeded
          if current_count >= max_verifications then
            return {current_count, ttl, 0, 1}  -- 1 = limit exceeded
          end

          -- Increment existing counter
          current_count = redis.call('INCR', key)
        else
          -- First request in this window
          was_new_key = 1
          redis.call('SETEX', key, rate_window, '1')
          current_count = 1
          ttl = rate_window
        end

        return {current_count, ttl, was_new_key, 0}  -- 0 = not exceeded
      LUA

      # Check if DNS verification is rate limited for a domain.
      # Raises LimitExceeded if the domain has exceeded the verification limit.
      # On success, increments the counter.
      #
      # @param domain_id [String] The domain's unique identifier
      # @raise [Onetime::LimitExceeded] If rate limit is exceeded
      # @return [Hash] Rate limit status with :remaining and :reset_in keys
      def check_dns_rate_limit!(domain_id)
        return default_rate_limit_status if domain_id.to_s.empty?

        key = dns_rate_limit_key(domain_id)

        # Atomically check limit and increment if allowed via server-side Lua script
        current_count, ttl, _was_new_key, limit_exceeded = redis.eval(
          CHECK_AND_INCREMENT_SCRIPT,
          keys: [key],
          argv: [RATE_WINDOW, MAX_VERIFICATIONS],
        )

        if limit_exceeded == 1
          OT.li "[DnsRateLimiter] Domain #{domain_id[0..7]} rate limited: #{current_count}/#{MAX_VERIFICATIONS}, reset in #{ttl}s"
          raise Onetime::LimitExceeded.new(
            'DNS verification rate limit exceeded. Please wait before trying again.',
            retry_after: ttl > 0 ? ttl : RATE_WINDOW,
            attempts: current_count,
            max_attempts: MAX_VERIFICATIONS,
          )
        end

        remaining = MAX_VERIFICATIONS - current_count
        reset_in  = ttl > 0 ? ttl : RATE_WINDOW

        if remaining <= 2
          OT.li "[DnsRateLimiter] Domain #{domain_id[0..7]} approaching limit: #{current_count}/#{MAX_VERIFICATIONS}"
        end

        {
          remaining: remaining,
          reset_in: reset_in,
          current: current_count,
          limit: MAX_VERIFICATIONS,
        }
      end

      # Get current rate limit status without incrementing the counter.
      # Useful for displaying remaining attempts to users.
      #
      # @param domain_id [String] The domain's unique identifier
      # @return [Hash] Rate limit status with :remaining, :reset_in, :current, :limit keys
      def dns_rate_limit_status(domain_id)
        return default_rate_limit_status if domain_id.to_s.empty?

        key = dns_rate_limit_key(domain_id)

        # Batch read to avoid multiple network trips
        current_count, ttl = redis.pipelined do |pipe|
          pipe.get(key)
          pipe.ttl(key)
        end

        current_count = current_count.to_i
        remaining     = MAX_VERIFICATIONS - current_count
        reset_in      = ttl > 0 ? ttl : RATE_WINDOW

        {
          remaining: [remaining, 0].max,
          reset_in: current_count.positive? ? reset_in : nil,
          current: current_count,
          limit: MAX_VERIFICATIONS,
        }
      end

      # Clear rate limit for a domain (e.g., for administrative reset).
      #
      # @param domain_id [String] The domain's unique identifier
      # @return [void]
      def clear_dns_rate_limit!(domain_id)
        return if domain_id.to_s.empty?

        redis.del(dns_rate_limit_key(domain_id))
      end

      private

      def dns_rate_limit_key(domain_id)
        "dns:ratelimit:#{domain_id}"
      end

      def default_rate_limit_status
        {
          remaining: MAX_VERIFICATIONS,
          reset_in: nil,
          current: 0,
          limit: MAX_VERIFICATIONS,
        }
      end

      # Access to Redis connection via model's dbclient.
      # Uses CustomDomain's connection pool for consistency with domain operations.
      def redis
        Onetime::CustomDomain.dbclient
      end
    end
  end
end
