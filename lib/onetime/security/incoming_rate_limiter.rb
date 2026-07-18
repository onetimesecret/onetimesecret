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
    # — each tier's check and record is a single atomic Lua call, so concurrent
    # bursts cannot overshoot the cap):
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

      # Lua script that checks the lockout AND records the submission in one
      # atomic round trip. Unlike LoginRateLimiter's split check/record (which
      # tolerates a bounded burst overshoot), a concurrent burst here cannot
      # exceed the cap: Redis serializes script executions, the increment that
      # reaches max_attempts sets the lockout flag and clears the counter, and
      # every later execution sees the flag and is denied before incrementing.
      # Returns {1, current_count} when allowed, {0, lockout_ttl} when denied.
      CHECK_AND_RECORD_SCRIPT = <<~LUA
        local attempts_key = KEYS[1]
        local lockout_key = KEYS[2]
        local attempt_window = tonumber(ARGV[1])
        local max_attempts = tonumber(ARGV[2])
        local lockout_duration = tonumber(ARGV[3])

        if redis.call('EXISTS', lockout_key) == 1 then
          return {0, redis.call('TTL', lockout_key)}
        end

        local current = redis.call('INCR', attempts_key)

        if current == 1 then
          redis.call('EXPIRE', attempts_key, attempt_window)
        end

        if current >= max_attempts then
          redis.call('SETEX', lockout_key, lockout_duration, '1')
          redis.call('DEL', attempts_key)
        end

        return {1, current}
      LUA

      # Enforce the incoming-submission rate limit and record this submission.
      # Raises LimitExceeded if either tier is locked; a locked tier is never
      # incremented (the Lua script denies before INCR). Tiers are evaluated
      # IP-first, so a submission denied by the recipient backstop still counts
      # against its IP. No-op when the limiter is disabled by config.
      #
      # @param client_ip [String, nil] The caller's edge-masked client IP.
      # @param recipient [String, nil] The client-supplied recipient hash.
      # @raise [Onetime::LimitExceeded] If either tier's limit is exceeded.
      # @return [void]
      def enforce_incoming_rate_limit!(client_ip, recipient = nil)
        return unless incoming_rate_limit_enabled?

        # Per-IP first (the tighter gate): a locked IP is rejected before the
        # recipient tier is touched, so it never inflates the recipient count.
        if (ip_keys   = incoming_ip_keys(client_ip))
          enforce_incoming_tier!(ip_keys, incoming_max_per_ip, 'ip', client_ip)
        end
        if (rcpt_keys = incoming_recipient_keys(recipient))
          enforce_incoming_tier!(rcpt_keys, incoming_max_per_recipient, 'recipient', recipient)
        end
      end

      private

      # Atomically check-and-record one tier via CHECK_AND_RECORD_SCRIPT.
      # Raises LimitExceeded when the tier is locked; otherwise logs as the
      # count approaches/reaches the cap.
      def enforce_incoming_tier!(keys, max_attempts, tier_label, subject)
        allowed, detail = incoming_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [incoming_window, max_attempts, incoming_lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            'Too many incoming secret submissions. Please try again later.',
            retry_after: detail.to_i.positive? ? detail.to_i : incoming_lockout,
            max_attempts: max_attempts,
          )
        end

        count = detail.to_i
        if count >= max_attempts
          OT.le "[IncomingRateLimiter] #{tier_label} #{obscured_incoming_subject(tier_label, subject)} locked for #{incoming_lockout}s after #{count} submissions"
        elsif count >= max_attempts - 1
          OT.li "[IncomingRateLimiter] #{tier_label} #{obscured_incoming_subject(tier_label, subject)} at #{count}/#{max_attempts} submissions"
        end
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
