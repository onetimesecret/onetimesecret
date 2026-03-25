# lib/onetime/security/ip_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # IPRateLimiter - Prevents abuse via per-IP rate limiting
    #
    # Provides per-IP rate limiting for API endpoints using Redis.
    # Configurable limits and windows allow different endpoints to have
    # appropriate limits based on their risk profile.
    #
    # Redis keys:
    #   - ratelimit:{event}:{ip} - Counter of requests (expires with window)
    #
    # Usage:
    #   include Onetime::Security::IPRateLimiter
    #
    #   def raise_concerns
    #     check_ip_rate_limit!('feedback', max: 10, window: 3600)
    #   end
    #
    module IPRateLimiter
      # Default rate limit window (1 hour in seconds)
      DEFAULT_WINDOW = 3600

      # Default maximum requests per window
      DEFAULT_MAX = 100

      # Lua script for atomic INCR + EXPIRE (prevents race condition
      # where a crash between the two commands leaves a permanent key).
      # NOTE: Redis EVAL runs Lua scripts server-side for atomicity.
      RATE_LIMIT_LUA = <<~LUA
        local c = redis.call('INCR', KEYS[1])
        if tonumber(c) == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
        return c
      LUA

      # Check if IP-based rate limit is exceeded for an event.
      # Raises LimitExceeded if the rate limit is exceeded.
      #
      # @param event [String] Name of the event/endpoint being rate limited
      # @param max [Integer] Maximum requests allowed per window (default: 100)
      # @param window [Integer] Window size in seconds (default: 3600)
      # @raise [Onetime::LimitExceeded] If rate limit is exceeded
      # @return [void]
      def check_ip_rate_limit!(event, max: DEFAULT_MAX, window: DEFAULT_WINDOW)
        ip = client_ip_address
        return if ip.to_s.empty?

        key = ip_rate_limit_key(event, ip)

        begin
          # Atomic INCR + EXPIRE via Lua script (Redis EVAL command).
          # Without atomicity, a crash between INCR and EXPIRE could leave
          # a permanent key that never expires.
          count = Familia.dbclient.eval(RATE_LIMIT_LUA, keys: [key], argv: [window])

          if count > max
            ttl = Familia.dbclient.ttl(key)
            raise Onetime::LimitExceeded.new(
              'Rate limit exceeded. Please try again later.',
              retry_after: ttl.positive? ? ttl : window,
              max_attempts: max,
            )
          end
        rescue Redis::BaseError => ex
          # Fail open: if Redis is down, don't block the request
          OT.le "[IPRateLimiter] Redis error: #{ex.class}: #{ex.message}"
        end
      end

      # Get the current request count for an IP/event combination.
      # Useful for monitoring or testing.
      #
      # @param event [String] Name of the event
      # @param ip [String] IP address (optional, defaults to current request IP)
      # @return [Integer] Current count, or 0 if no requests recorded
      def ip_rate_limit_count(event, ip = nil)
        ip ||= client_ip_address
        return 0 if ip.to_s.empty?

        Familia.dbclient.get(ip_rate_limit_key(event, ip)).to_i
      end

      private

      def ip_rate_limit_key(event, ip)
        "ratelimit:#{event}:#{ip}"
      end

      # Get client IP address from the request environment.
      # Logic classes have access to `req` via their base class.
      def client_ip_address
        if respond_to?(:req) && req.respond_to?(:client_ipaddress)
          req.client_ipaddress.to_s
        elsif respond_to?(:env) && env.is_a?(Hash)
          # Fallback for Rack environments
          forwarded_for = env['HTTP_X_FORWARDED_FOR']&.split(',')&.first
          forwarded_for&.strip ||
            env['HTTP_X_REAL_IP'] ||
            env['REMOTE_ADDR']
        end
      end
    end
  end
end
