# lib/onetime/security/email_auth_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'

module Onetime
  module Security
    # EmailAuthRateLimiter - Throttles unauthenticated magic-link requests
    #
    # Closes finding L-5 of the 2026-08-02 audit: POST /auth/email-login-request
    # (Rodauth's email_auth_request route) relied solely on the built-in
    # email_auth_skip_resend_email_within throttle, which is PER ACCOUNT — it
    # bounds resends for one mailbox but caps nothing across addresses. The
    # reachable primitive is unauthenticated, unthrottled magic-link email
    # dispatch: one login-link email per DISTINCT registered address per
    # request, from any origin, limited only per-target. This limiter is
    # ADDITIVE per-IP protection; the per-account resend throttle stays.
    #
    # SINGLE CALL SITE, by construction. The email_auth feature exists only in
    # FULL auth mode — the Auth app owns /auth/* whenever it is mounted, and in
    # simple mode there is no magic-link request endpoint at all (GET
    # /email-login in apps/web/core/routes.txt renders the SPA page; the POST
    # it would submit to does not exist). Enforcement lives in the Rodauth
    # before_email_auth_request_route hook
    # (apps/web/auth/config/hooks/email_auth_request.rb), at the top of the
    # route and therefore ahead of the account_from_login lookup and the
    # key INSERT + email send in _email_auth_request.
    #
    # SINGLE TIER, IP ONLY — the same shape as the account-creation limiter and
    # for a related reason. A per-email backstop here would key on the SUBMITTED
    # login before any account lookup, which is fine for abuse bounding but
    # redundant: Rodauth's email_auth_skip_resend_email_within already bounds
    # per-account sends (that is the mitigating factor the audit records), so
    # the gap is purely cross-address volume per origin — which only an IP tier
    # caps.
    #
    # ENUMERATION SAFETY: the tier keys ONLY on the client IP — never on the
    # submitted login, and never on whether it resolves to an account — so a
    # 429 discloses nothing about registration state.
    #
    # ORDERING: enforced from before_email_auth_request_route, which Rodauth
    # runs at the top of the route — ahead of the POST body and the
    # account_from_login lookup — but AFTER Rodauth's own
    # check_already_logged_in on the line above it. The already-authenticated
    # exclusion is deliberate: a signed-in caller hitting this route is a UI
    # mistake, not the abuse this bounds, and charging them budget would let
    # one authenticated user's stray form posts consume a shared masked-IP
    # bucket. Submissions for unknown addresses DO cost budget — they are free
    # to generate and a limiter that only counted successful sends would leak
    # registration state through its own bookkeeping.
    #
    # IP GRANULARITY, and the COLLAPSE CONDITION: the subject is the
    # privacy-masked network (/24 IPv4, /48 IPv6) the universal
    # IPPrivacyMiddleware resolved, so the bucket is shared by that
    # neighborhood; and with site.network.trusted_proxy disabled behind a
    # reverse proxy the resolved IP is the PROXY's address for every request,
    # collapsing the whole deployment into one bucket. A collapsed lockout here
    # denies passwordless login deployment-wide (password login is unaffected),
    # hence the deliberately loose default cap and the self-contained operator
    # hint appended to the lockout log line.
    #
    # CLEARING A STUCK LOCKOUT — same two paths as every other limiter, over
    # kind `email_auth_ip`:
    #
    #   1. `bin/ots ratelimit keys email_auth_ip <masked-ip>` piped to
    #      valkey-cli (the CLI only PRINTS commands). <masked-ip> is the STORED
    #      subject — the privacy-masked address, not the raw one and not the
    #      /16-obscured form in the log line.
    #   2. `POST /api/colonel/ratelimit/reset` with kind=email_auth_ip, which
    #      performs the delete AND records an AdminAuditEvent.
    #
    # Fail semantics mirror the other security limiters: Redis errors propagate
    # rather than silently permitting an unthrottled mail flood.
    #
    # Redis keys (string keys at the Redis boundary):
    #   - email_auth:attempts:ip:{ip}  - per-IP request counter
    #   - email_auth:locked:ip:{ip}    - per-IP lockout flag
    #
    # Config (site.authentication.email_auth_rate_limit): enabled, max_per_ip,
    # window, lockout. Absent config -> enabled with the constant defaults
    # below; set enabled:false to disable (the test config does, so suite
    # magic-link requests are not throttled).
    #
    # Usage (the hook file does exactly this, including the module into the
    # Rodauth class via auth_class_eval):
    #   include Onetime::Security::EmailAuthRateLimiter
    #   enforce_email_auth_rate_limit!(client_ip) # before any account lookup
    module EmailAuthRateLimiter
      # Default magic-link requests permitted per window from a single masked
      # client IP. Deliberately loose relative to what one PERSON needs (one
      # link, maybe a retry): the bucket is a whole masked /24, and under the
      # collapse condition above it can be the entire deployment — a tight cap
      # there is a passwordless-login outage. 10/hour matches the sibling
      # signup limiter and still turns unbounded mail dispatch into a bounded,
      # loggable, auditable trickle.
      DEFAULT_MAX_PER_IP = 10

      # Default window in seconds over which requests are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Default lockout duration in seconds once the cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Audit verb recorded when the tier reaches its cap. Namespaced
      # `<resource>.<action>` like every other verb in the trail; the admin
      # console filters on the exact string, so it is a constant.
      AUDIT_VERB = 'auth.email_auth_throttled'

      # Lua script that checks the lockout AND records the request in one
      # atomic round trip — same contract as {IncomingRateLimiter}: Redis
      # serializes script executions, the increment that reaches max_attempts
      # sets the lockout flag and clears the counter, and every later
      # execution sees the flag and is denied before incrementing, so
      # concurrent bursts cannot overshoot the cap.
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

      # Enforce the magic-link request rate limit and record this request.
      # Raises LimitExceeded when the IP is locked; a locked tier is never
      # incremented (the Lua script denies before INCR). No-op when the
      # limiter is disabled by config, and no-op when no client IP is
      # available — see email_auth_ip_keys for why that skips rather than
      # shares a bucket.
      #
      # @param client_ip [String, nil] The caller's edge-masked client IP.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_email_auth_rate_limit!(client_ip)
        return unless email_auth_rate_limit_enabled?
        return unless (keys = email_auth_ip_keys(client_ip))

        allowed, detail = email_auth_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [email_auth_window, email_auth_max_per_ip, email_auth_lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            'Too many login link requests. Please try again later.',
            retry_after: detail.to_i.positive? ? detail.to_i : email_auth_lockout,
            max_attempts: email_auth_max_per_ip,
          )
        end

        count = detail.to_i
        if count >= email_auth_max_per_ip
          # This cap-reaching request was itself ALLOWED (the Lua script locks
          # after incrementing); the lockout applies to subsequent requests.
          obscured = obscured_email_auth_ip(client_ip)
          OT.le "[EmailAuthRateLimiter] ip #{obscured} " \
                "hit cap (#{count}/#{email_auth_max_per_ip}); " \
                "locked for #{email_auth_lockout}s" \
                "#{collapsed_email_auth_ip_hint}"
          record_email_auth_throttle_audit(obscured, count)
        elsif count >= email_auth_max_per_ip - 1
          OT.li "[EmailAuthRateLimiter] ip #{obscured_email_auth_ip(client_ip)} " \
                "at #{count}/#{email_auth_max_per_ip} magic-link requests"
        end
      end

      private

      # Write the queryable counterpart of the OT.le line above, with a BOUNDED
      # WRITE FREQUENCY: it records ONLY on the cap-reaching request, never on
      # the deny path (which an attacker can drive as fast as it can send).
      # That bounds writes to one event per masked network per LOCKOUT window
      # (default 1h), so minting another costs a full cap's worth of requests
      # from another masked network. Pinned by tests; keep it.
      #
      # TRAIL SELECTION is feature-detected: newer trees split the audit store
      # into an operator trail (.record — count-capped with no TTL) and a
      # security trail (.record_security — its own count cap and age bound)
      # precisely so unauthenticated-triggerable writers cannot evict operator
      # records. When record_security exists it MUST be used; on trees that
      # predate the split, .record is acceptable only because of the
      # once-per-lockout-window bound above.
      #
      # The subject is the OBSCURED IP (/16), never the resolved one. Actor is
      # 'anonymous' — the caller is unauthenticated by construction on this
      # route (check_already_logged_in runs first), and normalize_actor would
      # otherwise stamp 'unknown', which reads as "we failed to resolve it"
      # rather than "there is none".
      #
      # Best-effort, matching every other audit call site.
      def record_email_auth_throttle_audit(obscured_ip, count)
        args = {
          actor: 'anonymous',
          verb: AUDIT_VERB,
          target: "ip:#{obscured_ip}",
          result: :failure,
          detail: {
            tier: 'ip',
            count: count,
            max_attempts: email_auth_max_per_ip,
            window: email_auth_window,
            lockout: email_auth_lockout,
          },
        }

        if Onetime::AdminAuditEvent.respond_to?(:record_security)
          Onetime::AdminAuditEvent.record_security(**args)
        else
          Onetime::AdminAuditEvent.record(**args)
        end
      rescue StandardError => ex
        # A magic-link request must never fail because its audit event could
        # not be assembled.
        OT.le('[EmailAuthRateLimiter] audit record failed', exception: ex)
      end

      # Composite per-IP keys, or nil when no IP is available.
      #
      # Skipping is correct rather than fail-closed here: a blank suffix would
      # build ONE key shared by every IP-less caller, so the first few would
      # lock the bucket and every later one would be denied — a global
      # passwordless-login outage driven by whatever made the IP unresolvable.
      # Same rationale as LoginRateLimiter#login_ip_keys. There is no second
      # tier to fall back on, but the per-account resend throttle
      # (email_auth_skip_resend_email_within) still bounds the per-mailbox
      # damage, so the hole is smaller than the signup limiter's.
      def email_auth_ip_keys(client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: "email_auth:attempts:ip:#{client_ip}",
          lockout: "email_auth:locked:ip:#{client_ip}",
        }
      end

      def email_auth_rate_limit_config
        OT.conf.dig('site', 'authentication', 'email_auth_rate_limit') || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config
      # keeps the protective default on; the test config disables it so suite
      # magic-link requests are not throttled.
      def email_auth_rate_limit_enabled?
        email_auth_rate_limit_config.fetch('enabled', true) != false
      end

      def email_auth_max_per_ip
        positive_email_auth_setting('max_per_ip', DEFAULT_MAX_PER_IP)
      end

      def email_auth_window
        positive_email_auth_setting('window', DEFAULT_WINDOW)
      end

      def email_auth_lockout
        positive_email_auth_setting('lockout', DEFAULT_LOCKOUT)
      end

      # Read a numeric setting, falling back to its default unless the
      # configured value coerces to a POSITIVE integer. A zero/garbage value
      # (a typo'd env var: `to_i` turns "abc" into 0) would otherwise invert
      # enforcement — a zero cap locks on the first request and a non-positive
      # lockout makes the Lua SETEX fail, turning every magic-link request
      # into a 500 instead of a throttle.
      def positive_email_auth_setting(key, default)
        value = email_auth_rate_limit_config[key].to_i
        value.positive? ? value : default
      end

      # Obscure the IP for logs: IPv4 keeps the /16, IPv6 is truncated to a
      # short prefix. The resolved value never reaches logs.
      def obscured_email_auth_ip(client_ip)
        value = client_ip.to_s
        parts = value.split('.')
        return "#{parts[0]}.#{parts[1]}.x.x" if parts.length == 4

        value[0..8]
      end

      # Operator diagnostic appended to the lockout LOG LINE (server side only
      # — it never reaches a response body) when the deployment has not
      # declared a trusted reverse proxy, in which case the resolved client IP
      # is REMOTE_ADDR and every visitor shares one bucket. Self-contained on
      # purpose: it restates the condition and names both remedy env vars
      # inline, so an operator reading only the log line has the whole
      # diagnosis. Keep it that way — do not swap it for a doc pointer.
      #
      # Deliberately NOT a boot-time check: the same config is correct for a
      # direct-connect deployment and boot has no evidence a proxy exists, so
      # a boot warning would fire on every default install. A lockout is the
      # first moment the condition is actually demonstrated.
      def collapsed_email_auth_ip_hint
        return '' if OT.conf.dig('site', 'network', 'trusted_proxy', 'enabled') == true

        '. NOTE: site.network.trusted_proxy is not enabled, so the client IP is ' \
          'REMOTE_ADDR; if this deployment is behind a reverse proxy every visitor ' \
          'shares this bucket and passwordless login is blocked deployment-wide. Set ' \
          'TRUSTED_PROXY_ENABLED=true, or raise EMAIL_AUTH_RATE_LIMIT_MAX_PER_IP'
      end

      # Redis connection via the Customer model's dbclient — the subject is a
      # login attempt on the auth surface, so the counters live on the same
      # shard as the login rate-limit state (matches LoginRateLimiter).
      def email_auth_redis
        Onetime::Customer.dbclient
      end
    end
  end
end
