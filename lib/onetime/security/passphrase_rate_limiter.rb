# lib/onetime/security/passphrase_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # PassphraseRateLimiter - Prevents brute-force attacks on secret passphrases
    #
    # Two-tier design (M-8). Keying the lockout solely on the secret identifier
    # let any holder of the secret link burn a handful of wrong guesses and impose
    # a lockout on the legitimate recipient (a targeted DoS). We therefore gate on
    # TWO independent tiers:
    #
    #   1. Per-secret+IP tier (the tight gate): keyed on secret_id + client_ip and
    #      locked at MAX_ATTEMPTS. This is what actually stops a given client after
    #      a few wrong guesses, without punishing other clients of the same secret.
    #   2. Per-secret global backstop: keyed on secret_id only and locked at the
    #      much higher GLOBAL_MAX_ATTEMPTS. It catches an IP-rotating attacker and
    #      callers with no IP (they share this bucket by secret). The threshold is
    #      high enough that a single legitimate recipient behind one IP won't trip
    #      it, but low enough to bound a distributed brute force.
    #
    # A missing client_ip FALLS BACK to the global tier only (it never builds a
    # "...:" composite key, which would collapse every anonymous caller into one
    # shared bucket and re-create the DoS). check() locks if EITHER tier is locked;
    # record() increments BOTH tiers; clear() clears BOTH.
    #
    # Note: in production metadata[:ip] is already /24-masked upstream, so the
    # per-IP tier is /24-granular. That coarseness is acceptable precisely because
    # the global backstop remains.
    #
    # Redis keys:
    #   - passphrase:attempts:{secret_id}            - global attempt counter
    #   - passphrase:locked:{secret_id}              - global lockout flag
    #   - passphrase:attempts:{secret_id}:{ip}       - per-IP attempt counter
    #   - passphrase:locked:{secret_id}:{ip}         - per-IP lockout flag
    #
    # Usage:
    #   include Onetime::Security::PassphraseRateLimiter
    #
    #   # In raise_concerns or before passphrase check:
    #   check_passphrase_rate_limit!(secret.identifier, client_ip)
    #
    #   # After failed passphrase attempt:
    #   record_failed_passphrase_attempt!(secret.identifier, client_ip)
    #
    module PassphraseRateLimiter
      # Maximum failed attempts allowed for the tight per-secret+IP tier. This is
      # the threshold that actually gates the lockout for a given client.
      MAX_ATTEMPTS = 5

      # Maximum failed attempts allowed for the per-secret global backstop tier.
      # Deliberately high so a single legitimate recipient behind one IP does not
      # trip it, while an IP-rotating / distributed attacker still eventually hits
      # it. This tier is the safety net when the per-IP tier can't help (no IP,
      # shared proxy IP, or a spoofed X-Forwarded-For).
      GLOBAL_MAX_ATTEMPTS = 20

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
      # Raises LimitExceeded if EITHER the per-IP tier or the global backstop is
      # locked out due to too many failures.
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @param client_ip [String, nil] The caller's (edge-masked) client IP. When
      #   present the tight per-secret+IP tier is enforced; when nil only the
      #   global per-secret backstop applies.
      # @raise [Onetime::LimitExceeded] If either tier's rate limit is exceeded
      # @return [void]
      def check_passphrase_rate_limit!(secret_identifier, client_ip = nil)
        return if secret_identifier.to_s.empty?

        # Tight per-secret+IP tier first: the real gate, checked before the looser
        # global backstop so an attacker IP is stopped at MAX_ATTEMPTS.
        if (ip_keys = passphrase_ip_keys(secret_identifier, client_ip))
          enforce_passphrase_tier_lock!(secret_identifier, ip_keys[:lockout], ip_keys[:attempts], MAX_ATTEMPTS)
        end

        # Global per-secret backstop: catches IP-rotating attackers and nil-IP
        # callers, who all share this bucket by secret.
        enforce_passphrase_tier_lock!(
          secret_identifier,
          passphrase_lockout_key(secret_identifier),
          passphrase_attempts_key(secret_identifier),
          GLOBAL_MAX_ATTEMPTS,
        )
      end

      # Record a failed passphrase attempt for a secret, incrementing BOTH the
      # global backstop and (when an IP is supplied) the per-secret+IP tier.
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @param client_ip [String, nil] The caller's (edge-masked) client IP
      # @return [Integer] Current attempt count for the tightest tier that
      #   applied (the per-IP count when an IP was supplied, else the global
      #   count) -- suitable for surfacing in caller logs.
      def record_failed_passphrase_attempt!(secret_identifier, client_ip = nil)
        return 0 if secret_identifier.to_s.empty?

        # Always increment the global per-secret backstop.
        global_count = record_passphrase_tier!(
          passphrase_attempts_key(secret_identifier),
          passphrase_lockout_key(secret_identifier),
          GLOBAL_MAX_ATTEMPTS,
        )
        if global_count >= GLOBAL_MAX_ATTEMPTS
          OT.le "[PassphraseRateLimiter] Secret #{secret_identifier[0..7]} global backstop locked for #{LOCKOUT_DURATION}s after #{global_count} failed attempts"
        end

        # Increment the per-secret+IP tier when an IP is available; its count is
        # the one surfaced to callers since it drives the tight lockout.
        reported_count = global_count
        if (ip_keys    = passphrase_ip_keys(secret_identifier, client_ip))
          ip_count       = record_passphrase_tier!(ip_keys[:attempts], ip_keys[:lockout], MAX_ATTEMPTS)
          if ip_count >= MAX_ATTEMPTS
            OT.le "[PassphraseRateLimiter] Secret #{secret_identifier[0..7]} locked for one client for #{LOCKOUT_DURATION}s after #{ip_count} failed attempts"
          end
          reported_count = ip_count
        end

        reported_count
      end

      # Clear rate limit state for a secret (call on successful passphrase entry).
      # Clears both the global backstop and, when an IP is supplied, the per-IP
      # tier so a legitimate recipient is not held under a stale per-IP lockout.
      #
      # @param secret_identifier [String] The secret's unique identifier
      # @param client_ip [String, nil] The caller's (edge-masked) client IP
      # @return [void]
      def clear_passphrase_rate_limit!(secret_identifier, client_ip = nil)
        return if secret_identifier.to_s.empty?

        keys        = [
          passphrase_attempts_key(secret_identifier),
          passphrase_lockout_key(secret_identifier),
        ]
        if (ip_keys = passphrase_ip_keys(secret_identifier, client_ip))
          keys.push(ip_keys[:attempts], ip_keys[:lockout])
        end

        redis.del(*keys)
      end

      private

      # Enforce a single tier's lockout: raise LimitExceeded if the tier is
      # locked, otherwise log when it is one attempt short of its threshold.
      def enforce_passphrase_tier_lock!(secret_identifier, lockout_key, attempts_key, max_attempts)
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
            max_attempts: max_attempts,
          )
        end

        current_attempts = current_attempts.to_i

        # Log if approaching limit (for monitoring)
        if current_attempts >= max_attempts - 1
          OT.li "[PassphraseRateLimiter] Secret #{secret_identifier[0..7]} at #{current_attempts}/#{max_attempts} attempts"
        end
      end

      # Atomically increment a single tier's counter and set TTLs / lockout via
      # the Lua script. Returns the counter value after increment.
      def record_passphrase_tier!(attempts_key, lockout_key, max_attempts)
        redis.eval(
          RECORD_ATTEMPT_SCRIPT,
          keys: [attempts_key, lockout_key],
          argv: [ATTEMPT_WINDOW, max_attempts, LOCKOUT_DURATION],
        )
      end

      # Composite per-secret+IP keys, or nil when no IP is available. Returning
      # nil (rather than building a "...:" key) is what makes nil-IP callers fall
      # back to the global backstop instead of sharing one poisoned bucket.
      def passphrase_ip_keys(secret_identifier, client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: passphrase_attempts_key(secret_identifier, client_ip),
          lockout: passphrase_lockout_key(secret_identifier, client_ip),
        }
      end

      def passphrase_attempts_key(secret_identifier, client_ip = nil)
        base = "passphrase:attempts:#{secret_identifier}"
        client_ip.to_s.empty? ? base : "#{base}:#{client_ip}"
      end

      def passphrase_lockout_key(secret_identifier, client_ip = nil)
        base = "passphrase:locked:#{secret_identifier}"
        client_ip.to_s.empty? ? base : "#{base}:#{client_ip}"
      end

      # Access to Redis connection via Secret model's dbclient
      # This ensures we use the same connection pool as the models
      def redis
        Onetime::Secret.dbclient
      end
    end
  end
end
