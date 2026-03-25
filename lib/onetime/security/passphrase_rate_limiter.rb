# lib/onetime/security/passphrase_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # PassphraseRateLimiter - Prevents brute-force attacks on secret passphrases
    #
    # Tracks failed passphrase attempts per secret identifier using Redis.
    # After MAX_ATTEMPTS failures within ATTEMPT_WINDOW, the secret is locked
    # for LOCKOUT_DURATION to prevent further attempts.
    #
    # Redis keys:
    #   - passphrase:attempts:{secret_id} - Counter of failed attempts (expires with ATTEMPT_WINDOW)
    #   - passphrase:locked:{secret_id} - Lockout flag (expires with LOCKOUT_DURATION)
    #
    # Usage:
    #   include Onetime::Security::PassphraseRateLimiter
    #
    #   # In raise_concerns or before passphrase check:
    #   check_passphrase_rate_limit!(secret.identifier)
    #
    #   # After failed passphrase attempt:
    #   record_failed_passphrase_attempt!(secret.identifier)
    #
    module PassphraseRateLimiter
      # Maximum failed attempts allowed per secret
      MAX_ATTEMPTS = 5

      # Window in seconds for counting attempts (10 minutes)
      ATTEMPT_WINDOW = 600

      # Lockout duration in seconds after max attempts exceeded (30 minutes)
      LOCKOUT_DURATION = 1800

      # Lua script to atomically increment attempts and handle expiration/lockout
      RECORD_ATTEMPT_SCRIPT = <<~LUA
        local attempts_key = KEYS[1]
        local lockout_key = KEYS[2]
        local attempt_window = tonumber(ARGV[1])
        local max_attempts = tonumber(ARGV[2])
        local lockout_duration = tonumber(ARGV[3])

        local current_attempts = redis.call('INCR', attempts_key)

        if current_attempts == 1 then
          redis.call('EXPIRE', attempts_key, attempt_window)
        end

        if current_attempts >= max_attempts then
          redis.call('SETEX', lockout_key, lockout_duration, '1')
          redis.call('DEL', attempts_key)
        end

        return current_attempts
      LUA

      # Check if passphrase attempts are rate limited for a secret.
      # Raises LimitExceeded if the secret is locked out due to too many failures.
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @raise [Onetime::LimitExceeded] If rate limit is exceeded
      # @return [void]
      def check_passphrase_rate_limit!(secret_identifier)
        return if secret_identifier.to_s.empty?

        lockout_key  = passphrase_lockout_key(secret_identifier)
        attempts_key = passphrase_attempts_key(secret_identifier)

        # Batch operations to avoid multiple Redis network trips
        is_locked, ttl, current_attempts = redis.pipelined do |pipe|
          pipe.exists?(lockout_key)
          pipe.ttl(lockout_key)
          pipe.get(attempts_key)
        end

        # Handle different redis-rb version return types for exists?
        if [true, 1].include?(is_locked)
          raise Onetime::LimitExceeded.new(
            'Too many incorrect passphrase attempts. Please try again later.',
            retry_after: ttl > 0 ? ttl : LOCKOUT_DURATION,
            max_attempts: MAX_ATTEMPTS,
          )
        end

        current_attempts = current_attempts.to_i

        # Log if approaching limit (for monitoring)
        if current_attempts >= MAX_ATTEMPTS - 1
          OT.li "[PassphraseRateLimiter] Secret #{secret_identifier[0..7]} at #{current_attempts}/#{MAX_ATTEMPTS} attempts"
        end
      end

      # Record a failed passphrase attempt for a secret.
      # After MAX_ATTEMPTS failures, creates a lockout that blocks further attempts.
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @return [Integer] Current attempt count after increment
      def record_failed_passphrase_attempt!(secret_identifier)
        return 0 if secret_identifier.to_s.empty?

        attempts_key = passphrase_attempts_key(secret_identifier)
        lockout_key  = passphrase_lockout_key(secret_identifier)

        # Atomically increment and set TTLs via Lua script
        current_attempts = redis.eval(
          RECORD_ATTEMPT_SCRIPT,
          keys: [attempts_key, lockout_key],
          argv: [ATTEMPT_WINDOW, MAX_ATTEMPTS, LOCKOUT_DURATION],
        )

        if current_attempts >= MAX_ATTEMPTS
          OT.le "[PassphraseRateLimiter] Secret #{secret_identifier[0..7]} locked for #{LOCKOUT_DURATION}s after #{current_attempts} failed attempts"
        end

        current_attempts
      end

      # Clear rate limit state for a secret (call on successful passphrase entry)
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @return [void]
      def clear_passphrase_rate_limit!(secret_identifier)
        return if secret_identifier.to_s.empty?

        redis.del(
          passphrase_attempts_key(secret_identifier),
          passphrase_lockout_key(secret_identifier),
        )
      end

      private

      def passphrase_attempts_key(secret_identifier)
        "passphrase:attempts:#{secret_identifier}"
      end

      def passphrase_lockout_key(secret_identifier)
        "passphrase:locked:#{secret_identifier}"
      end

      # Access to Redis connection via Secret model's dbclient
      # This ensures we use the same connection pool as the models
      def redis
        Onetime::Secret.dbclient
      end
    end
  end
end
