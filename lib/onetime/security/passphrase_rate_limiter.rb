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

      # Check if passphrase attempts are rate limited for a secret.
      # Raises LimitExceeded if the secret is locked out due to too many failures.
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @raise [Onetime::LimitExceeded] If rate limit is exceeded
      # @return [void]
      def check_passphrase_rate_limit!(secret_identifier)
        return if secret_identifier.to_s.empty?

        lockout_key = passphrase_lockout_key(secret_identifier)

        # Check if currently locked out
        if redis.exists?(lockout_key)
          ttl = redis.ttl(lockout_key)
          raise Onetime::LimitExceeded.new(
            'Too many incorrect passphrase attempts. Please try again later.',
            retry_after: ttl > 0 ? ttl : LOCKOUT_DURATION,
            max_attempts: MAX_ATTEMPTS,
          )
        end

        # Check current attempt count (informational, doesn't block yet)
        attempts_key     = passphrase_attempts_key(secret_identifier)
        current_attempts = redis.get(attempts_key).to_i

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

        # Increment attempt counter atomically
        current_attempts = redis.incr(attempts_key)

        # Set expiration on first attempt
        if current_attempts == 1
          redis.expire(attempts_key, ATTEMPT_WINDOW)
        end

        # If max attempts exceeded, create lockout
        if current_attempts >= MAX_ATTEMPTS
          redis.setex(lockout_key, LOCKOUT_DURATION, '1')

          # Clear attempts counter (lockout now governs access)
          redis.del(attempts_key)

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
