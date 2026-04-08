# lib/onetime/security/invite_token_rate_limiter.rb
#
# frozen_string_literal: true

require 'ipaddr'

module Onetime
  module Security
    # InviteTokenRateLimiter - Prevents token enumeration attacks on invite endpoints
    #
    # Tracks invite token lookup attempts per IP address using Redis.
    # After MAX_ATTEMPTS within WINDOW_SECONDS, further attempts are blocked
    # until the lockout expires.
    #
    # This protects against:
    #   - Brute-force token guessing attacks
    #   - Token enumeration by malicious actors
    #   - Abuse of the noauth invite endpoints
    #
    # Redis keys:
    #   - invite_attempts:{ip} - Counter of attempts (expires with WINDOW_SECONDS)
    #   - invite_locked:{ip} - Lockout flag (expires with LOCKOUT_SECONDS)
    #
    # Usage:
    #   limiter = Onetime::Security::InviteTokenRateLimiter.new(req.ip)
    #   limiter.check!           # Raises LimitExceeded if locked out
    #   limiter.record_attempt   # Call on every attempt
    #   limiter.reset!           # Clear on successful invite action (optional)
    #
    class InviteTokenRateLimiter
      # Maximum attempts allowed per IP within the window
      MAX_ATTEMPTS = 100

      # Window in seconds for counting attempts (10 minutes)
      WINDOW_SECONDS = 600

      # Lockout duration in seconds after max attempts exceeded (20 minutes)
      LOCKOUT_SECONDS = 1200

      class << self
        # Force rate limiting even in test environment (for unit testing the limiter)
        attr_accessor :force_enabled
      end
      self.force_enabled = false

      # Lua script to atomically increment attempts and handle expiration/lockout.
      # Returns: [current_attempts, limit_exceeded, ttl]
      #
      # NOTE: redis.call('EVAL', ...) executes server-side Lua, not Ruby eval.
      # This is the standard Redis atomic scripting pattern.
      RECORD_ATTEMPT_SCRIPT = <<~LUA
        local attempts_key = KEYS[1]
        local lockout_key = KEYS[2]
        local window_seconds = tonumber(ARGV[1])
        local max_attempts = tonumber(ARGV[2])
        local lockout_seconds = tonumber(ARGV[3])

        local current_attempts = redis.call('INCR', attempts_key)

        -- Always refresh TTL to ensure consistent cleanup on every request
        redis.call('EXPIRE', attempts_key, window_seconds)

        local limit_exceeded = 0
        local ttl = redis.call('TTL', attempts_key)

        if current_attempts >= max_attempts then
          redis.call('SETEX', lockout_key, lockout_seconds, '1')
          redis.call('DEL', attempts_key)
          limit_exceeded = 1
          ttl = lockout_seconds
        end

        return {current_attempts, limit_exceeded, ttl}
      LUA

      attr_reader :ip_address

      def initialize(ip_address)
        @ip_address = sanitize_ip(ip_address)
      end

      # Check if the IP is currently locked out.
      # Raises LimitExceeded if locked.
      #
      # @raise [Onetime::LimitExceeded] If rate limit lockout is active
      # @return [void]
      def check!
        return if @ip_address.empty?
        return if test_bypass? # Bypass rate limiting in test environment

        is_locked, ttl = redis.pipelined do |pipe|
          pipe.exists?(lockout_key)
          pipe.ttl(lockout_key)
        end

        # Handle different redis-rb version return types for exists?
        return unless [true, 1].include?(is_locked)

        OT.li "[InviteTokenRateLimiter] IP #{obscured_ip} is locked out, #{ttl}s remaining"
        raise Onetime::LimitExceeded.new(
          'Too many invite requests. Please try again later.',
          retry_after: ttl > 0 ? ttl : LOCKOUT_SECONDS,
          max_attempts: MAX_ATTEMPTS,
        )
      end

      # Record an attempt and create lockout if max attempts reached.
      # Uses atomic Lua script for thread safety.
      #
      # @return [Hash] Status with :attempts, :locked, :retry_after keys
      def record_attempt
        return { attempts: 0, locked: false } if @ip_address.empty?
        return { attempts: 0, locked: false } if test_bypass? # Bypass in test environment

        current_attempts, limit_exceeded, ttl = run_record_script

        locked = limit_exceeded == 1

        if locked
          OT.le "[InviteTokenRateLimiter] IP #{obscured_ip} locked after #{current_attempts} attempts"
        elsif current_attempts >= MAX_ATTEMPTS - 2
          OT.li "[InviteTokenRateLimiter] IP #{obscured_ip} approaching limit: #{current_attempts}/#{MAX_ATTEMPTS}"
        end

        {
          attempts: current_attempts,
          locked: locked,
          retry_after: locked ? ttl : nil,
        }
      end

      # Check if currently rate limited (without raising).
      #
      # @return [Boolean] true if locked out
      def rate_limited?
        return false if @ip_address.empty?

        is_locked = redis.exists?(lockout_key)
        [true, 1].include?(is_locked)
      end

      # Get remaining attempts before lockout.
      #
      # @return [Integer] Attempts remaining (0 if locked)
      def attempts_remaining
        return MAX_ATTEMPTS if @ip_address.empty?
        return 0 if rate_limited?

        current = redis.get(attempts_key).to_i
        [MAX_ATTEMPTS - current, 0].max
      end

      # Clear rate limit state for this IP.
      # Call on successful invite action if desired.
      #
      # @return [void]
      def reset!
        return if @ip_address.empty?

        redis.del(attempts_key, lockout_key)
      end

      private

      # Check if rate limiting should be bypassed in test environment.
      # Returns true if RACK_ENV=test and force_enabled is not set.
      # Note: OT.env returns 'testing' when RACK_ENV=test
      def test_bypass?
        OT.env?(:testing) && !self.class.force_enabled
      end

      # Execute the Lua script via Redis EVAL command (server-side execution)
      def run_record_script
        redis.evalsha(
          script_sha,
          keys: [attempts_key, lockout_key],
          argv: [WINDOW_SECONDS, MAX_ATTEMPTS, LOCKOUT_SECONDS],
        )
      rescue Redis::CommandError => ex
        # Script not cached, load and retry
        raise unless ex.message.include?('NOSCRIPT')

        redis.script(:load, RECORD_ATTEMPT_SCRIPT)
        retry
      end

      def script_sha
        @script_sha ||= Digest::SHA1.hexdigest(RECORD_ATTEMPT_SCRIPT)
      end

      def attempts_key
        @attempts_key ||= "invite_attempts:#{@ip_address}"
      end

      def lockout_key
        @lockout_key ||= "invite_locked:#{@ip_address}"
      end

      # Sanitize and validate IP address using Ruby's IPAddr
      # Returns canonical form of the IP or empty string if invalid
      def sanitize_ip(ip)
        return '' if ip.nil? || ip.to_s.strip.empty?

        begin
          parsed = IPAddr.new(ip.to_s.strip)
          parsed.to_s
        rescue IPAddr::InvalidAddressError
          OT.ld "[InviteTokenRateLimiter] Invalid IP address rejected: #{ip.to_s[0..20]}"
          ''
        end
      end

      # Obscure IP for logging (show first part only)
      def obscured_ip
        return 'empty' if @ip_address.empty?

        if @ip_address.include?(':')
          # IPv6: show first segment
          @ip_address.split(':').first + ':***'
        else
          # IPv4: show first two octets
          parts = @ip_address.split('.')
          "#{parts[0]}.#{parts[1]}.*.*"
        end
      end

      # Access to Redis connection via model's dbclient
      def redis
        Onetime::Secret.dbclient
      end
    end
  end
end
