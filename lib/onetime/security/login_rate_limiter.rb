# lib/onetime/security/login_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # LoginRateLimiter - Throttles simple-mode credential submissions
    #
    # Simple auth mode verifies credentials in
    # Core::Logic::Authentication::AuthenticateSession (there is no Rodauth
    # lockout in this mode). Without a limiter that path accepts unlimited
    # password guesses. This module caps failed attempts per account using a
    # TWO-TIER design (RL-2 / RL-3), structurally identical to
    # {PassphraseRateLimiter}:
    #
    #   1. Per-email+IP tier (the tight gate): keyed on email + client_ip and
    #      locked at MAX_ATTEMPTS. This is what actually stops a given origin
    #      after a few wrong guesses, without punishing other clients of the
    #      same account.
    #   2. Per-email global backstop: keyed on email only and locked at the
    #      much higher GLOBAL_MAX_ATTEMPTS. It catches an IP-rotating botnet —
    #      which, keyed on the composite alone, would get 5·N guesses against a
    #      single account with NO aggregate cap (RL-2) — and it bounds nil-IP
    #      callers, who all share this bucket by email.
    #
    # A missing client_ip FALLS BACK to the global tier only (it never builds an
    # "email:" composite key). This is the RL-3 fix: an email-only *tight*
    # lockout (5) would let one attacker lock a victim out from ALL IPs after a
    # handful of guesses — a targeted-account DoS. With no IP we skip the tight
    # tier entirely; the global backstop still bounds the attacker, but only at
    # the much higher (and much harder to weaponize) GLOBAL_MAX_ATTEMPTS.
    #
    # check() locks if EITHER tier is locked; record() increments BOTH
    # applicable tiers; clear() clears BOTH.
    #
    # Redis keys:
    #   - login:attempts:{email}         - global attempt counter
    #   - login:locked:{email}           - global lockout flag
    #   - login:attempts:{email}:{ip}    - per-IP attempt counter
    #   - login:locked:{email}:{ip}      - per-IP lockout flag
    #
    # Operator note: the per-IP keys carry a variable {ip} suffix, so they are
    # reached by the Reset/Inspect ops via the registry's SCAN patterns (the
    # 'login' entry's :scan_keys), NOT by the static-key `bin/ots ratelimit
    # keys` output. Keep these templates byte-identical with that registry entry.
    #
    # Usage:
    #   include Onetime::Security::LoginRateLimiter
    #
    #   check_login_rate_limit!(email, client_ip)      # first line of raise_concerns
    #   record_failed_login_attempt!(email, client_ip) # in the failure branch
    #   clear_login_rate_limit!(email, client_ip)      # on a verified login
    #
    module LoginRateLimiter
      # Maximum failed attempts for the tight per-email+IP tier. This is the
      # threshold that actually gates the lockout for a given origin.
      MAX_ATTEMPTS = 5

      # Maximum failed attempts for the per-email global backstop. Deliberately
      # high so a legitimate user cycling through a few IPs (mobile hand-off,
      # VPN) does not trip it, while an IP-rotating / distributed attacker is
      # still capped at this many guesses per window against a single account.
      GLOBAL_MAX_ATTEMPTS = 30

      # Window in seconds for counting failed attempts (15 minutes)
      ATTEMPT_WINDOW = 900

      # Lockout duration after exceeding a tier's limit (30 minutes)
      LOCKOUT_DURATION = 1800

      # Lua script to atomically increment attempts and handle expiration/lockout
      RECORD_ATTEMPT_SCRIPT = <<~LUA
        local attempts_key = KEYS[1]
        local lockout_key = KEYS[2]
        local attempt_window = tonumber(ARGV[1])
        local max_attempts = tonumber(ARGV[2])
        local lockout_duration = tonumber(ARGV[3])

        local current = redis.call('INCR', attempts_key)

        if current == 1 then
          redis.call('EXPIRE', attempts_key, attempt_window)
        end

        if current >= max_attempts then
          redis.call('SETEX', lockout_key, lockout_duration, '1')
          redis.call('DEL', attempts_key)
        end

        return current
      LUA

      # Check whether login attempts are rate limited for an email/IP pair.
      # Raises LimitExceeded if EITHER the per-IP tier or the global backstop is
      # locked out due to too many failures.
      #
      # @param email [String] The account email (the rate-limit subject)
      # @param client_ip [String, nil] The caller's (edge-masked) client IP.
      #   When present the tight per-email+IP tier is enforced; when nil only
      #   the global per-email backstop applies.
      # @raise [Onetime::LimitExceeded] If either tier's rate limit is exceeded
      # @return [void]
      def check_login_rate_limit!(email, client_ip = nil)
        return if email.to_s.empty?

        # Tight per-email+IP tier first: the real gate, checked before the looser
        # global backstop so an attacker origin is stopped at MAX_ATTEMPTS.
        if (ip_keys = login_ip_keys(email, client_ip))
          enforce_login_tier_lock!(email, ip_keys[:lockout], ip_keys[:attempts], MAX_ATTEMPTS)
        end

        # Global per-email backstop: catches IP-rotating attackers and nil-IP
        # callers, who all share this bucket by email.
        enforce_login_tier_lock!(
          email,
          login_lockout_key(email),
          login_attempts_key(email),
          GLOBAL_MAX_ATTEMPTS,
        )
      end

      # Record a failed login attempt, incrementing BOTH the global backstop and
      # (when an IP is supplied) the per-email+IP tier.
      #
      # @param email [String] The account email
      # @param client_ip [String, nil] The caller's (edge-masked) client IP
      # @return [Integer] Current attempt count for the tightest tier that
      #   applied (the per-IP count when an IP was supplied, else the global
      #   count) -- suitable for surfacing in caller logs.
      def record_failed_login_attempt!(email, client_ip = nil)
        return 0 if email.to_s.empty?

        # Always increment the per-email global backstop.
        global_count = record_login_tier!(
          login_attempts_key(email),
          login_lockout_key(email),
          GLOBAL_MAX_ATTEMPTS,
        )
        if global_count >= GLOBAL_MAX_ATTEMPTS
          OT.le "[LoginRateLimiter] email #{OT::Utils.obscure_email(email)} global backstop locked for #{LOCKOUT_DURATION}s after #{global_count} attempts"
        end

        # Increment the per-email+IP tier when an IP is available; its count is
        # the one surfaced to callers since it drives the tight lockout.
        reported_count = global_count
        if (ip_keys    = login_ip_keys(email, client_ip))
          ip_count       = record_login_tier!(ip_keys[:attempts], ip_keys[:lockout], MAX_ATTEMPTS)
          if ip_count >= MAX_ATTEMPTS
            OT.le "[LoginRateLimiter] subject #{obscured_subject(email, client_ip)} locked for #{LOCKOUT_DURATION}s after #{ip_count} attempts"
          end
          reported_count = ip_count
        end

        reported_count
      end

      # Clear rate limit state for an email (verified login / admin reset path).
      # Clears the global backstop and, when an IP is supplied, the per-IP tier
      # so a legitimate user is not held under a stale per-IP lockout.
      #
      # @param email [String] The account email
      # @param client_ip [String, nil] The caller's (edge-masked) client IP
      # @return [void]
      def clear_login_rate_limit!(email, client_ip = nil)
        return if email.to_s.empty?

        keys        = [
          login_attempts_key(email),
          login_lockout_key(email),
        ]
        if (ip_keys = login_ip_keys(email, client_ip))
          keys.push(ip_keys[:attempts], ip_keys[:lockout])
        end

        login_redis.del(*keys)
      end

      private

      # Enforce a single tier's lockout: raise LimitExceeded if the tier is
      # locked, otherwise log when it is one attempt short of its threshold.
      def enforce_login_tier_lock!(email, lockout_key, attempts_key, max_attempts)
        # Batch operations to avoid multiple Redis network trips
        is_locked, ttl, current = login_redis.pipelined do |pipe|
          pipe.exists?(lockout_key)
          pipe.ttl(lockout_key)
          pipe.get(attempts_key)
        end

        # Handle different redis-rb version return types for exists?
        if [true, 1].include?(is_locked)
          raise Onetime::LimitExceeded.new(
            'Too many login attempts. Please try again later.',
            retry_after: ttl > 0 ? ttl : LOCKOUT_DURATION,
            max_attempts: max_attempts,
          )
        end

        current = current.to_i

        # Log if approaching limit (for monitoring)
        if current >= max_attempts - 1
          OT.li "[LoginRateLimiter] email #{OT::Utils.obscure_email(email)} at #{current}/#{max_attempts} attempts"
        end
      end

      # Atomically increment a single tier's counter and set TTLs / lockout via
      # the Lua script. Returns the counter value after increment.
      def record_login_tier!(attempts_key, lockout_key, max_attempts)
        login_redis.eval(
          RECORD_ATTEMPT_SCRIPT,
          keys: [attempts_key, lockout_key],
          argv: [ATTEMPT_WINDOW, max_attempts, LOCKOUT_DURATION],
        )
      end

      # Composite per-email+IP keys, or nil when no IP is available. Returning
      # nil (rather than building an "email:" key) is what makes nil-IP callers
      # fall back to the global backstop instead of a tight email-only lockout
      # that any attacker could weaponize against a victim (RL-3).
      def login_ip_keys(email, client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: login_attempts_key(email, client_ip),
          lockout: login_lockout_key(email, client_ip),
        }
      end

      def login_attempts_key(email, client_ip = nil)
        base = "login:attempts:#{email}"
        client_ip.to_s.empty? ? base : "#{base}:#{client_ip}"
      end

      def login_lockout_key(email, client_ip = nil)
        base = "login:locked:#{email}"
        client_ip.to_s.empty? ? base : "#{base}:#{client_ip}"
      end

      # Obscure the email + IP for logs so we never store a full email or client
      # address in operational output.
      def obscured_subject(email, client_ip)
        "#{OT::Utils.obscure_email(email)}|#{obscured_ip(client_ip)}"
      end

      # Obscure the IP for logs. IPv4 keeps the /16; IPv6 keeps the first
      # nine characters (roughly the routed prefix).
      def obscured_ip(ip_address)
        parts = ip_address.to_s.split('.')
        if parts.length == 4
          "#{parts[0]}.#{parts[1]}.x.x"
        else
          ip_address.to_s[0..8]
        end
      end

      # Access to Redis connection via the Customer model's dbclient, so login
      # attempts and lockouts live on the same shard as the account records the
      # email is derived from.
      def login_redis
        Onetime::Customer.dbclient
      end
    end
  end
end
