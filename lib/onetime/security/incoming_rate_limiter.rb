# lib/onetime/security/incoming_rate_limiter.rb
#
# frozen_string_literal: true

module Onetime
  module Security
    # IncomingRateLimiter - Throttles anonymous incoming-secret submissions
    #
    # The incoming feature (apps/api/incoming) accepts anonymous POSTs that both
    # create an encrypted secret and enqueue an email to a pre-configured
    # recipient. Without a throttle a single origin can drive unbounded secret
    # writes and outbound mail. This module caps submissions using the same
    # two-tier + Lua-lockout shape as {LoginRateLimiter}, adapted for a plain
    # rate limiter (every submission is an "attempt"; there is no failure branch
    # — check and record happen together on each request):
    #
    #   1. Per-IP tier (the primary gate): keyed on the edge-masked client IP and
    #      capped at MAX_PER_IP. Stops a given origin after a handful of
    #      submissions per window without punishing other clients.
    #   2. Per-recipient tier (backstop): keyed on the client-supplied recipient
    #      HASH and capped at the higher MAX_PER_RECIPIENT. Bounds an IP-rotating
    #      attacker spamming one recipient, and also caps nil-IP callers, who all
    #      share this bucket by recipient.
    #
    # A missing client_ip skips the IP tier entirely (it never builds an
    # "ip:" key with a blank suffix); the per-recipient backstop still applies.
    # A missing recipient (malformed submission) skips the recipient tier. If
    # neither is available the limiter is a no-op — such a request fails the
    # presence checks in raise_concerns anyway.
    #
    # Fail semantics mirror LoginRateLimiter: Redis errors propagate (the caller
    # runs this inside raise_concerns, where a surfaced error rejects the request
    # rather than silently permitting an unthrottled write).
    #
    # Redis keys (string keys at the Redis boundary):
    #   - incoming:attempts:ip:{ip}       - per-IP submission counter
    #   - incoming:locked:ip:{ip}         - per-IP lockout flag
    #   - incoming:attempts:rcpt:{hash}   - per-recipient submission counter
    #   - incoming:locked:rcpt:{hash}     - per-recipient lockout flag
    #
    # Config (features.incoming.rate_limit): enabled, max_per_ip,
    # max_per_recipient, window, lockout. Absent config -> enabled with the
    # constant defaults below; set enabled:false to disable (test/opt-out).
    #
    # Usage:
    #   include Onetime::Security::IncomingRateLimiter
    #   enforce_incoming_rate_limit!(client_ip, recipient_hash) # in raise_concerns,
    #                                                            # before any write
    module IncomingRateLimiter
      # Default per-IP submissions permitted per window (~10/hour per IP).
      DEFAULT_MAX_PER_IP = 10

      # Default per-recipient backstop. Higher than the IP cap so a legitimate
      # recipient receiving from several origins is not throttled, while an
      # IP-rotating spammer is still bounded.
      DEFAULT_MAX_PER_RECIPIENT = 30

      # Default window in seconds over which submissions are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Default lockout duration in seconds once a tier's cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Lua script to atomically increment a tier's counter and set its
      # expiry/lockout. Identical shape to LoginRateLimiter's script: on the
      # increment that reaches max_attempts it sets the lockout flag and clears
      # the counter, so the NEXT check raises.
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

      # Enforce the incoming-submission rate limit and record this submission.
      # Raises LimitExceeded if EITHER tier is already locked from prior
      # submissions; otherwise records the current submission against every
      # applicable tier. No-op when the limiter is disabled by config.
      #
      # @param client_ip [String, nil] The caller's edge-masked client IP.
      # @param recipient [String, nil] The client-supplied recipient hash.
      # @raise [Onetime::LimitExceeded] If either tier's limit is exceeded.
      # @return [void]
      def enforce_incoming_rate_limit!(client_ip, recipient = nil)
        return unless incoming_rate_limit_enabled?

        # Check both tiers before recording so a locked origin is rejected
        # without adding to its counter.
        if (ip_keys   = incoming_ip_keys(client_ip))
          enforce_incoming_tier_lock!(ip_keys[:lockout], ip_keys[:attempts], incoming_max_per_ip, 'ip', client_ip)
        end
        if (rcpt_keys = incoming_recipient_keys(recipient))
          enforce_incoming_tier_lock!(rcpt_keys[:lockout], rcpt_keys[:attempts], incoming_max_per_recipient, 'recipient', recipient)
        end

        record_incoming_submission!(client_ip, recipient)
      end

      private

      # Raise LimitExceeded if the tier is locked; otherwise log when approaching
      # the cap. Mirrors LoginRateLimiter#enforce_login_tier_lock!.
      def enforce_incoming_tier_lock!(lockout_key, attempts_key, max_attempts, tier_label, subject)
        is_locked, ttl, current = incoming_redis.pipelined do |pipe|
          pipe.exists?(lockout_key)
          pipe.ttl(lockout_key)
          pipe.get(attempts_key)
        end

        if [true, 1].include?(is_locked)
          raise Onetime::LimitExceeded.new(
            'Too many incoming secret submissions. Please try again later.',
            retry_after: ttl.to_i > 0 ? ttl : incoming_lockout,
            max_attempts: max_attempts,
          )
        end

        current = current.to_i
        if current >= max_attempts - 1
          OT.li "[IncomingRateLimiter] #{tier_label} #{obscured_incoming_subject(tier_label, subject)} at #{current}/#{max_attempts} submissions"
        end
      end

      # Record this submission against both applicable tiers.
      def record_incoming_submission!(client_ip, recipient)
        if (ip_keys   = incoming_ip_keys(client_ip))
          count = record_incoming_tier!(ip_keys[:attempts], ip_keys[:lockout], incoming_max_per_ip)
          if count >= incoming_max_per_ip
            OT.le "[IncomingRateLimiter] ip #{obscured_incoming_subject('ip', client_ip)} locked for #{incoming_lockout}s after #{count} submissions"
          end
        end
        if (rcpt_keys = incoming_recipient_keys(recipient))
          count = record_incoming_tier!(rcpt_keys[:attempts], rcpt_keys[:lockout], incoming_max_per_recipient)
          if count >= incoming_max_per_recipient
            OT.le "[IncomingRateLimiter] recipient #{obscured_incoming_subject('recipient', recipient)} locked for #{incoming_lockout}s after #{count} submissions"
          end
        end
      end

      def record_incoming_tier!(attempts_key, lockout_key, max_attempts)
        incoming_redis.eval(
          RECORD_ATTEMPT_SCRIPT,
          keys: [attempts_key, lockout_key],
          argv: [incoming_window, max_attempts, incoming_lockout],
        )
      end

      # Composite per-IP keys, or nil when no IP is available (skips the IP tier
      # rather than building a blank-suffixed key — same rationale as
      # LoginRateLimiter#login_ip_keys).
      def incoming_ip_keys(client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: "incoming:attempts:ip:#{client_ip}",
          lockout: "incoming:locked:ip:#{client_ip}",
        }
      end

      # Composite per-recipient keys, or nil when no recipient hash was supplied.
      def incoming_recipient_keys(recipient)
        return nil if recipient.to_s.empty?

        {
          attempts: "incoming:attempts:rcpt:#{recipient}",
          lockout: "incoming:locked:rcpt:#{recipient}",
        }
      end

      def incoming_rate_limit_config
        OT.conf.dig('features', 'incoming', 'rate_limit') || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config keeps
      # the protective default on; the :test config disables it so existing
      # incoming tryouts are not throttled.
      def incoming_rate_limit_enabled?
        incoming_rate_limit_config.fetch('enabled', true) != false
      end

      def incoming_max_per_ip
        (incoming_rate_limit_config['max_per_ip'] || DEFAULT_MAX_PER_IP).to_i
      end

      def incoming_max_per_recipient
        (incoming_rate_limit_config['max_per_recipient'] || DEFAULT_MAX_PER_RECIPIENT).to_i
      end

      def incoming_window
        (incoming_rate_limit_config['window'] || DEFAULT_WINDOW).to_i
      end

      def incoming_lockout
        (incoming_rate_limit_config['lockout'] || DEFAULT_LOCKOUT).to_i
      end

      # Obscure the subject for logs. IPv4 keeps the /16; the recipient hash and
      # IPv6 are truncated to a short prefix so full values never reach logs.
      def obscured_incoming_subject(tier_label, subject)
        value = subject.to_s
        if tier_label == 'ip'
          parts = value.split('.')
          return "#{parts[0]}.#{parts[1]}.x.x" if parts.length == 4
        end
        value[0..8]
      end

      # Redis connection via the shared Familia client. Incoming submissions are
      # anonymous, so (unlike LoginRateLimiter) there is no account shard to
      # co-locate with.
      def incoming_redis
        Familia.dbclient
      end
    end
  end
end
