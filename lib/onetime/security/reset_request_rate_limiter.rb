# lib/onetime/security/reset_request_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'

module Onetime
  module Security
    # ResetRequestRateLimiter - Throttles reset-password-request submissions
    #
    # Enforced on BOTH auth-mode paths to POST /auth/reset-password-request:
    #
    #   - full mode: the Rodauth before_reset_password_request_route hook
    #     (apps/web/auth/config/hooks/reset_password_request.rb), ahead of the
    #     route body;
    #   - simple mode (the application default): the shared logic class,
    #     AccountAPI::Logic::Authentication::ResetPasswordRequest#raise_concerns
    #     (routed via apps/web/core/routes.txt →
    #     Core::Controllers::Registration#request_reset_email), ahead of the
    #     format check and the account lookup.
    #
    # Only one of the two paths is reachable in a given deployment (the auth app
    # owns /auth/* when mounted), so this is parity of PROTECTION, not double
    # counting. The IP subject is identical in both (env['otto.client_ip']). The
    # login subject is NOT byte-identical across modes and does not need to be:
    # each mode passes the exact string IT uses to look the account up — Rodauth's
    # normalize_login in full mode, sanitize_email in simple mode — which is the
    # property that matters. Because each mode feeds one function's output to both
    # the limiter and its own lookup, one account can never occupy two buckets in
    # the mode that is running; where the two modes' normalizations differ (e.g.
    # simple mode's HTML sanitization turns `a&b@x` into `a&amp;b@x`) the effect is
    # to MERGE distinct submissions into one bucket, never to split one target
    # across several. Counters are therefore not interchangeable across a
    # simple->full migration; nothing depends on them being so.
    #
    # The enumeration-safe reset-password-request route (#3857) returns an
    # identical response for every login, which closed the single-request
    # content oracle but left a statistical TIMING residual: a hit performs
    # reset-key writes and an email dispatch a miss does not. Beating network/
    # Puma/GC jitter with that residual needs MANY samples per target (error
    # shrinks ~1/sqrt(N)), so capping request volume is the direct way to bound
    # the attack's throughput (#3872). Rodauth's own resend throttle
    # (reset_password_email_recently_sent?) is per-account and caps EMAILS, not
    # request volume — it does nothing against one source probing many different
    # logins, which is exactly the enumeration sampling pattern.
    #
    # Two tiers, using the same atomic check-and-record shape as
    # {IncomingRateLimiter} (every submission is an "attempt"; there is no
    # failure branch — each tier's check and record is a single Lua call, so
    # concurrent bursts cannot overshoot the cap):
    #
    #   1. Per-IP tier (the primary gate): keyed on the edge-masked client IP
    #      and capped at MAX_PER_IP. Stops a given origin after a handful of
    #      requests per window regardless of how many logins it cycles through.
    #   2. Per-email tier (backstop): keyed on the NORMALIZED submitted login
    #      and capped at the higher MAX_PER_EMAIL. Bounds an IP-rotating /
    #      distributed attacker sampling one target, and also caps nil-IP
    #      callers, who all share this bucket by login.
    #
    # IP GRANULARITY: the "client IP" is the value the universal
    # IPPrivacyMiddleware mount resolves and privacy-masks BEFORE the app sees
    # it — /24 for IPv4, /48 for IPv6 (Otto::Privacy::IPPrivacy,
    # octet_precision 1). The per-IP bucket is therefore shared by that masked
    # network neighborhood, exactly like every other IP-keyed limiter in this
    # codebase (IncomingRateLimiter, the sso-link-confirm throttle, the
    # LoginRateLimiter email+IP tier): the raw address never survives the
    # privacy middleware, so no finer key exists downstream. A hostile
    # neighbor in the same masked network can thus consume the shared budget
    # and 429 the reset-request route for the neighborhood for one lockout
    # window — bounded, repeatable-only-with-effort, and the accepted cost of
    # IP privacy. Operators with dense NAT populations can raise
    # RESET_REQUEST_RATE_LIMIT_MAX_PER_IP; the per-email backstop is
    # unaffected by IP granularity.
    #
    # WHY THE TIGHT TIER IS IP-ONLY (and must stay that way): the composite
    # tight tiers elsewhere in lib/onetime/security/ — LoginRateLimiter's
    # email+IP, PassphraseRateLimiter's secret+IP — gate a GUESS AGAINST A
    # NAMED SUBJECT, where an email-only tight lockout would be a weapon
    # (RL-3: one attacker locks a victim out from every IP with five
    # requests). This limiter gates VOLUME FROM A SOURCE: both abuse shapes
    # it exists to bound (timing samples across many targets, mail-bombing
    # arbitrary addresses) iterate the LOGIN, so an ip+login tight key would
    # grant max_per_ip requests per attacker-chosen login with no aggregate
    # cap at all — exactly the uncapped state #3872/#3950 closed. The IP-only
    # tier is the only thing capping total throughput per origin, and it is
    # the same shape as the other anonymous-submission throttles
    # (IncomingRateLimiter's ip: tier, FeedbackRateLimiter,
    # InviteTokenRateLimiter), not an anomaly.
    #
    # COLLAPSE CONDITION (operators): the tier is only as granular as the
    # resolved client IP. With site.network.trusted_proxy.enabled false (the
    # default) Otto ignores X-Forwarded-For entirely and resolves REMOTE_ADDR
    # (Otto::Utils.resolve_client_ip) — which, behind a reverse proxy, is the
    # PROXY's address for every request. Masked, that is ONE bucket for the
    # whole deployment: max_per_ip resets per window for all users combined,
    # then a lockout-length outage of the reset flow. Correct for a
    # direct-connect deployment, silently wrong behind an unconfigured proxy —
    # so the remedy is configuration, not keying (no key scheme can separate
    # many-users-one-address from one-attacker-many-logins; the two are
    # identical in every dimension the limiter can observe). Set
    # TRUSTED_PROXY_ENABLED=true, or raise
    # RESET_REQUEST_RATE_LIMIT_MAX_PER_IP and lean on the per-email backstop,
    # which is unaffected. While the config is in that state,
    # enforce_reset_request_tier! appends collapsed_ip_tier_hint's
    # SELF-CONTAINED one-line summary to the IP-tier lockout log: it restates
    # the condition and names both remedy env vars inline, so the log line
    # stands alone (it cites no file or section, deliberately — see that
    # method).
    #
    # CLEARING A STUCK LOCKOUT. Two supported paths, both over the SAME keys:
    #
    #   1. `bin/ots ratelimit keys reset_request_ip <masked-ip>` — this PRINTS
    #      `TTL`/`GET`/`DEL` command text and never touches the datastore
    #      itself (see lib/onetime/cli/ratelimit_command.rb), so it only
    #      recovers anything once piped:
    #
    #        bin/ots ratelimit keys reset_request_ip <masked-ip> \
    #          | grep -v '^#' | valkey-cli
    #
    #      <masked-ip> is the STORED subject — the privacy-masked address
    #      (/24 IPv4, /48 IPv6), NOT the raw address and NOT the /16-obscured
    #      form obscured_reset_request_subject puts in the log line. Enumerate
    #      the live ones with
    #      `valkey-cli --scan --pattern 'reset_request:locked:ip:*'`.
    #   2. `POST /api/colonel/ratelimit/reset` with `kind=reset_request_ip`
    #      and `subject=<masked-ip>` (colonel role; ColonelAPI::Logic::Colonel::
    #      ResetRateLimit -> Onetime::Operations::RateLimit::Reset). Unlike the
    #      CLI this performs the delete AND records an AdminAuditEvent.
    #
    # The per-email cap is deliberately the LOOSER tier (mirroring
    # LoginRateLimiter's global backstop, RL-3): a TIGHT per-email lockout
    # would let an attacker deny a victim's reset flow from all IPs with a
    # handful of requests. The higher cap keeps that targeted-DoS expensive
    # while still bounding distributed timing samples per target per window —
    # and the impact of a deliberate per-email lockout is itself bounded:
    # Rodauth's resend throttle means the victim's reset email (once sent)
    # is not resent within its window anyway, and the lockout expires.
    #
    # ENUMERATION SAFETY: both tiers key ONLY on request-observable inputs
    # (client IP, submitted login string) — never on whether the login maps to
    # an account — so a 429 discloses nothing about account existence. The
    # login is normalized with the SAME helper Rodauth's normalize_login uses
    # (OT::Utils.normalize_email: strip + NFC + case-fold; see config/base.rb)
    # so every variant Rodauth would resolve to one account lands in one
    # per-target bucket — plain downcase would let Unicode case-fold/NFC
    # variants dodge the backstop. The check runs BEFORE Rodauth touches the
    # accounts table, so a throttled probe never reaches the timing-sensitive
    # path.
    #
    # A missing client_ip skips the IP tier entirely (it never builds an "ip:"
    # key with a blank suffix); the per-email backstop still applies. A missing
    # login skips the email tier. If neither is available the limiter is a
    # no-op — such a request fails Rodauth's own param validation anyway.
    #
    # Fail semantics mirror the other security limiters: Redis errors propagate
    # (a surfaced error rejects the request rather than silently permitting an
    # unthrottled probe).
    #
    # Redis keys (string keys at the Redis boundary):
    #   - reset_request:attempts:ip:{ip}        - per-IP request counter
    #   - reset_request:locked:ip:{ip}          - per-IP lockout flag
    #   - reset_request:attempts:email:{email}  - per-login request counter
    #   - reset_request:locked:email:{email}    - per-login lockout flag
    #
    # Config (site.authentication.reset_request_rate_limit): enabled,
    # max_per_ip, max_per_email, window, lockout. Absent config -> enabled with
    # the constant defaults below; set enabled:false to disable (the test
    # config does, so full-mode suite POSTs are not throttled).
    #
    # Usage:
    #   include Onetime::Security::ResetRequestRateLimiter
    #   enforce_reset_request_rate_limit!(client_ip, login) # before any
    #                                                        # account lookup
    module ResetRequestRateLimiter
      # Default requests permitted per window from a single client IP. The
      # tight gate: far above any legitimate per-user need (Rodauth sends at
      # most one email per account per resend window) while capping a single
      # origin's timing samples per window.
      DEFAULT_MAX_PER_IP = 10

      # Default per-login backstop. Higher than the IP cap so several
      # legitimate origins (user retrying from phone + laptop, a shared NAT)
      # are not throttled, while an IP-rotating attacker is still bounded to
      # this many samples per target per window.
      DEFAULT_MAX_PER_EMAIL = 30

      # Default window in seconds over which requests are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Default lockout duration in seconds once a tier's cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Longest login string a per-email key is built from. Anything longer is
      # truncated (not skipped) so oversized garbage still lands in SOME
      # bucket instead of minting unbounded-length Redis keys. 320 covers the
      # maximal legal email (64 local + '@' + 255 domain).
      MAX_EMAIL_KEY_LENGTH = 320

      # Audit verb recorded when a tier reaches its cap. Namespaced like every
      # other verb in the trail (`<resource>.<action>`); the admin console
      # filters on the exact string, so it is a constant rather than a literal.
      AUDIT_VERB = 'auth.reset_request_throttled'

      # ASCII control characters (C0 + DEL) removed from the normalized login
      # before it is used as a Redis-key suffix or log subject. An email can
      # never contain them, so distinct garbage strings merging into one
      # bucket is harmless — while newlines/escapes in keys or log lines are
      # not.
      CONTROL_CHAR_PATTERN = /[\u0000-\u001F\u007F]/

      # Lua script that checks the lockout AND records the request in one
      # atomic round trip (same contract as IncomingRateLimiter): Redis
      # serializes script executions, the increment that reaches max_attempts
      # sets the lockout flag and clears the counter, and every later
      # execution sees the flag and is denied before incrementing.
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

      # Enforce the reset-request rate limit and record this request. Raises
      # LimitExceeded if either tier is locked; a locked tier is never
      # incremented (the Lua script denies before INCR). Tiers are evaluated
      # IP-first, which makes the counting asymmetric by design: a request
      # denied by the IP tier never touches the email tier, while a request
      # denied by the email backstop has already consumed one IP-tier slot —
      # so every request an origin actually lands costs it IP budget. No-op
      # when the limiter is disabled by config.
      #
      # @param client_ip [String, nil] The caller's edge-masked client IP.
      # @param login [String, nil] The submitted login (target email), taken
      #   verbatim from the request params — existence is never consulted.
      # @raise [Onetime::LimitExceeded] If either tier's limit is exceeded.
      # @return [void]
      def enforce_reset_request_rate_limit!(client_ip, login = nil)
        return unless reset_request_rate_limit_enabled?

        # Per-IP first (the tighter gate): a locked IP is rejected before the
        # email tier is touched, so it never inflates the per-target count.
        if (ip_keys = reset_request_ip_keys(client_ip))
          enforce_reset_request_tier!(ip_keys, reset_request_max_per_ip, 'ip', client_ip)
        end

        # Normalize ONCE; the same value feeds the Redis key AND the
        # (obscured) log subject, so a raw attacker-supplied string never
        # reaches either.
        normalized     = normalize_reset_request_login(login)
        if (email_keys = reset_request_email_keys(normalized))
          enforce_reset_request_tier!(email_keys, reset_request_max_per_email, 'email', normalized)
        end
      end

      private

      # Atomically check-and-record one tier via CHECK_AND_RECORD_SCRIPT.
      # Raises LimitExceeded when the tier is locked; otherwise logs as the
      # count approaches/reaches the cap (the detection tie-in for #3872 —
      # alert on these alongside the reset_password_request_no_account events).
      # The cap-hit also writes one AdminAuditEvent, so the signal is queryable
      # and not only greppable — see record_reset_request_throttle_audit.
      def enforce_reset_request_tier!(keys, max_attempts, tier_label, subject)
        allowed, detail = reset_request_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [reset_request_window, max_attempts, reset_request_lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            'Too many password reset requests. Please try again later.',
            retry_after: detail.to_i.positive? ? detail.to_i : reset_request_lockout,
            max_attempts: max_attempts,
          )
        end

        count = detail.to_i
        if count >= max_attempts
          # This cap-reaching request was itself ALLOWED (the Lua script locks
          # after incrementing); the lockout applies to subsequent requests.
          obscured = obscured_reset_request_subject(tier_label, subject)
          OT.le "[ResetRequestRateLimiter] #{tier_label} #{obscured} " \
                "hit cap (#{count}/#{max_attempts}); locked for #{reset_request_lockout}s" \
                "#{collapsed_ip_tier_hint(tier_label)}"
          record_reset_request_throttle_audit(tier_label, obscured, count, max_attempts)
        elsif count >= max_attempts - 1
          OT.li "[ResetRequestRateLimiter] #{tier_label} #{obscured_reset_request_subject(tier_label, subject)} at #{count}/#{max_attempts} requests"
        end
      end

      # Write the queryable counterpart of the OT.le line above: one
      # {Onetime::AdminAuditEvent} per cap-hit, readable through the admin audit
      # view (GET /api/colonel/audit) and the CLI. A log line alone is not a
      # signal an operator can query — an enumeration attempt against the reset
      # flow otherwise leaves nothing to search for.
      #
      # WRITE FREQUENCY IS THE CONTROL. AdminAuditEvent is capped by COUNT with
      # no TTL, so an event an unauthenticated caller can trigger at will is a
      # log-eviction primitive (see the cap rationale on AdminAuditEvent and
      # {Onetime::AuditedFailure}). This records ONLY on the cap-reaching
      # request — never on the deny path, which an attacker can drive as fast as
      # it can send. That bounds writes to one per bucket per LOCKOUT window
      # (default 1h): minting another event requires another distinct masked
      # network or another distinct target login, each costing a full cap's
      # worth of requests. It is not free of the primitive — a distributed
      # attacker, or any attacker able to forge the resolved client IP behind an
      # appending reverse proxy, can still mint buckets — so an operator
      # relying on the admin trail must also ensure the proxy layer strips or
      # overwrites client-supplied forwarding headers rather than appending.
      #
      # The subject is the OBSCURED value (masked /16 for IPv4, obscured email),
      # never the raw login: the audit trail must not become the account
      # enumeration oracle the limiter exists to bound.
      #
      # Actor is 'anonymous' — the caller is unauthenticated by construction on
      # this route, and normalize_actor would otherwise stamp 'unknown', which
      # reads as "we failed to resolve it" rather than "there is none".
      #
      # Best-effort, matching every other audit call site: AdminAuditEvent.record
      # already swallows its own errors, and this rescue covers assembly.
      def record_reset_request_throttle_audit(tier_label, obscured_subject, count, max_attempts)
        Onetime::AdminAuditEvent.record(
          actor: 'anonymous',
          verb: AUDIT_VERB,
          target: "#{tier_label}:#{obscured_subject}",
          result: :failure,
          detail: {
            tier: tier_label,
            count: count,
            max_attempts: max_attempts,
            window: reset_request_window,
            lockout: reset_request_lockout,
          },
        )
      rescue StandardError => ex
        # A reset request must never fail because its audit event could not be
        # assembled.
        OT.le('[ResetRequestRateLimiter] audit record failed', exception: ex, tier: tier_label.to_s)
      end

      # Composite per-IP keys, or nil when no IP is available (skips the IP
      # tier rather than building a blank-suffixed key — same rationale as
      # LoginRateLimiter#login_ip_keys).
      def reset_request_ip_keys(client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: "reset_request:attempts:ip:#{client_ip}",
          lockout: "reset_request:locked:ip:#{client_ip}",
        }
      end

      # Composite per-login keys from the ALREADY-NORMALIZED login, or nil
      # when no login was submitted (skips the email tier rather than keying
      # a blank suffix).
      def reset_request_email_keys(normalized_login)
        return nil if normalized_login.empty?

        {
          attempts: "reset_request:attempts:email:#{normalized_login}",
          lockout: "reset_request:locked:email:#{normalized_login}",
        }
      end

      # Normalize the submitted login for keying and logging. Runs BEFORE
      # Rodauth validates the param, so this must tolerate arbitrary strings.
      #
      # Uses the SAME helper as Rodauth's normalize_login (config/base.rb →
      # OT::Utils.normalize_email: strip + NFC + case-fold), so every variant
      # Rodauth would resolve to one account shares one bucket, then removes
      # control characters and length-caps. Invalid encodings (which
      # normalize_email cannot process and which can never match an account —
      # Rodauth's own normalize_login is the same helper and would fail
      # identically later) are scrubbed rather than raised, so the probe still
      # consumes limiter budget instead of erroring here.
      def normalize_reset_request_login(login)
        value = begin
          OT::Utils.normalize_email(login)
        rescue StandardError
          login.to_s.scrub('').strip.downcase
        end
        value.gsub(CONTROL_CHAR_PATTERN, '')[0, MAX_EMAIL_KEY_LENGTH].to_s
      end

      def reset_request_rate_limit_config
        OT.conf.dig('site', 'authentication', 'reset_request_rate_limit') || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config
      # keeps the protective default on; the test config disables it so
      # full-mode specs are not throttled.
      def reset_request_rate_limit_enabled?
        reset_request_rate_limit_config.fetch('enabled', true) != false
      end

      def reset_request_max_per_ip
        positive_reset_request_setting('max_per_ip', DEFAULT_MAX_PER_IP)
      end

      def reset_request_max_per_email
        positive_reset_request_setting('max_per_email', DEFAULT_MAX_PER_EMAIL)
      end

      def reset_request_window
        positive_reset_request_setting('window', DEFAULT_WINDOW)
      end

      def reset_request_lockout
        positive_reset_request_setting('lockout', DEFAULT_LOCKOUT)
      end

      # Read a numeric setting, falling back to its default unless the
      # configured value coerces to a POSITIVE integer. A zero/garbage value
      # (e.g. a typo'd env var: `to_i` turns "abc" into 0) would otherwise
      # invert enforcement — a zero cap locks on the first request and a
      # non-positive lockout makes the Lua SETEX fail, turning every reset
      # request into a 500 instead of a throttle.
      def positive_reset_request_setting(key, default)
        value = reset_request_rate_limit_config[key].to_i
        value.positive? ? value : default
      end

      # Obscure the subject for logs. IPv4 keeps the /16; emails go through the
      # shared obscure helper; IPv6 is truncated to a short prefix. Full values
      # never reach logs.
      def obscured_reset_request_subject(tier_label, subject)
        value = subject.to_s
        if tier_label == 'ip'
          parts = value.split('.')
          return "#{parts[0]}.#{parts[1]}.x.x" if parts.length == 4

          return value[0..8]
        end
        OT::Utils.obscure_email(value)
      end

      # Operator diagnostic appended to the IP-TIER lockout LOG LINE (server
      # side only — it never reaches a response body) when the deployment has
      # not declared a trusted reverse proxy. In that config the resolved
      # client IP is REMOTE_ADDR, which is the proxy's own address when one is
      # in front, so every visitor shares one masked bucket and this lockout is
      # deployment-wide rather than per-origin (see COLLAPSE CONDITION above).
      #
      # The string is SELF-CONTAINED on purpose: it restates the condition and
      # names both remedy env vars inline rather than referring the reader to a
      # file or section, so an operator reading only the log line has the whole
      # diagnosis. Keep it that way — do not swap it for a doc pointer, and do
      # not grow it into a paragraph.
      #
      # Deliberately NOT a boot-time check: the same config is correct for a
      # direct-connect deployment and boot has no evidence a proxy exists, so a
      # boot warning would fire on every default install. An IP-tier lockout is
      # the first moment the condition is actually demonstrated. Returns '' in
      # every other case, so a correctly configured deployment's log line is
      # byte-identical to before. Nothing here varies on account existence.
      def collapsed_ip_tier_hint(tier_label)
        return '' unless tier_label == 'ip'
        return '' if OT.conf.dig('site', 'network', 'trusted_proxy', 'enabled') == true

        '. NOTE: site.network.trusted_proxy is not enabled, so the client IP is ' \
          'REMOTE_ADDR; if this deployment is behind a reverse proxy every visitor ' \
          'shares this bucket and the lockout is deployment-wide. Set ' \
          'TRUSTED_PROXY_ENABLED=true, or raise RESET_REQUEST_RATE_LIMIT_MAX_PER_IP'
      end

      # Redis connection via the Customer model's dbclient — the subject is an
      # email on the auth surface, so the counters live on the same shard as
      # the login/account rate-limit state (matches LoginRateLimiter).
      def reset_request_redis
        Onetime::Customer.dbclient
      end
    end
  end
end
