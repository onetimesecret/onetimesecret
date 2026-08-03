# lib/onetime/security/create_account_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'

module Onetime
  module Security
    # CreateAccountRateLimiter - Throttles unauthenticated account creation
    #
    # Closes finding #4 of the 2026-07-30 audit: POST /auth/create-account had
    # no limiter of any kind in EITHER auth mode. The reachable primitive is
    # unauthenticated, unthrottled account creation — one Customer record plus
    # one welcome email per DISTINCT address, with subaddressing (victim+1@,
    # victim+2@, ...) collapsing arbitrarily many addresses onto one mailbox.
    # Impact is datastore growth (the Customer hash carries no TTL) and
    # unsolicited mail.
    #
    # Enforced on BOTH auth-mode paths to POST /auth/create-account:
    #
    #   - full mode (what production runs): the Rodauth
    #     before_create_account_route hook (apps/web/auth/config/hooks/
    #     create_account.rb), at the top of the route and therefore ahead of the
    #     route body and of every before_create_account check;
    #   - simple mode (the application default for self-hosted installs): the
    #     shared logic class,
    #     AccountAPI::Logic::Account::CreateAccount#raise_concerns (routed via
    #     apps/web/core/routes.txt →
    #     Core::Controllers::Registration#create_account), ahead of the format
    #     and signup-domain checks and the Customer lookup.
    #
    # Only one of the two is reachable in a given deployment — the Auth app owns
    # /auth/* whenever it is mounted, and Rack::URLMap dispatches
    # longest-prefix-first (lib/onetime/application/registry.rb) — so this is
    # parity of PROTECTION, not double counting. Both take their subject from
    # env['otto.client_ip'], so in the mounted stack — where IPPrivacyMiddleware
    # always sets it — the keyspace and any operator remediation are identical
    # in either mode. The FALLBACKS differ and are unreachable there: full mode
    # falls back to Rack::Request#ip, simple mode to AuthStrategies::Helpers
    # #client_ip (Otto::Utils.resolve_client_ip, then Rack::Request#ip). Keep
    # the two call sites in lockstep on ORDERING and on the subject passed: a
    # change to one belongs in the other.
    #
    # Internal requests are excluded in full mode — the invite-signup path calls
    # Auth::Config.create_account via :internal_request, which runs the same
    # route block with a synthesized POST env, and it is already throttled by
    # {InviteTokenRateLimiter}. See the hook file for why that exclusion is
    # explicit rather than incidental.
    #
    # SINGLE TIER, IP ONLY — and unlike {ResetRequestRateLimiter} that is not a
    # tradeoff, it is the only tier that can work here. That limiter's per-email
    # backstop bounds an IP-rotating attacker sampling ONE target, because there
    # the target address is the thing held fixed. Account-creation abuse holds
    # nothing fixed: every request carries a fresh address, which is the point of
    # the attack. A per-email tier would mint one bucket per request and cap
    # nothing. Capping volume per origin is the whole of the available defense.
    #
    # NOT a per-mailbox tier either. Subaddress folding (strip +tag, and for the
    # major providers strip dots) would key victim+1@ and victim+2@ to one
    # bucket, which is the shape the mail-bombing case wants. It is deliberately
    # NOT done: the fold is provider-specific (gmail strips dots, others do not),
    # so a wrong guess silently merges DISTINCT people's addresses into one
    # bucket and one stranger's signups lock out another's. That is a worse
    # failure than the spam it prevents, for a LOW finding. The per-IP cap
    # already bounds total mail volume per origin, which is the same ceiling by a
    # safer key.
    #
    # ENUMERATION SAFETY: the tier keys ONLY on the client IP — never on the
    # submitted address, and never on whether it resolves to an account — so a
    # 429 discloses nothing. This matters more here than on the reset route:
    # CreateAccount's entire response contract is that existing and new accounts
    # are byte-identical (see #process), and a limiter keyed on anything
    # account-derived would have punched a hole straight through it.
    #
    # ORDERING — the same shape in both modes, before any account lookup or
    # write and after the already-authenticated guard:
    #
    #   - simple mode: enforced from #raise_concerns, ahead of the format and
    #     signup-domain checks and therefore ahead of the Customer.find_by_email
    #     lookup and Customer.create! in #process, but AFTER the
    #     already-authenticated guard on the first line of that method;
    #   - full mode: enforced from before_create_account_route, which Rodauth
    #     runs at the top of the route — ahead of the POST body, of the
    #     db[:accounts] lookup and Onetime::Customer.email_exists? check in the
    #     before_create_account hook, and of the account INSERT — but AFTER
    #     Rodauth's own check_already_logged_in on the line above it.
    #
    # The already-authenticated exclusion is deliberate in both: a signed-in
    # caller hitting this route is a UI mistake, not the abuse this bounds, and
    # charging them budget would let one authenticated user's stray form posts
    # consume a shared masked-IP bucket. Malformed and disallowed-domain
    # submissions DO cost budget — they are free to generate and equally good
    # for flooding.
    #
    # IP GRANULARITY, and the COLLAPSE CONDITION, are identical to
    # {ResetRequestRateLimiter}: the subject is the privacy-masked network (/24
    # IPv4, /48 IPv6) the universal IPPrivacyMiddleware resolved, so the bucket
    # is shared by that neighborhood; and with site.network.trusted_proxy
    # disabled behind a reverse proxy the resolved IP is the PROXY's address for
    # every request, collapsing the whole deployment into one bucket. Read that
    # module's COLLAPSE CONDITION section — the diagnosis and both remedies are
    # the same, and this limiter appends the same self-contained hint to its
    # lockout log line.
    #
    # The collapse matters MORE here than for reset requests. A reset-request
    # lockout denies a recovery flow to an already-registered user, who can wait
    # out the window; a create-account lockout denies SIGNUP to every new visitor
    # behind that address. Hence the deliberately loose default cap below.
    #
    # CLEARING A STUCK LOCKOUT — same two paths as every other limiter, over
    # kind `create_account_ip`:
    #
    #   1. `bin/ots ratelimit keys create_account_ip <masked-ip>` piped to
    #      valkey-cli (the CLI only PRINTS commands; see ratelimit_command.rb).
    #      <masked-ip> is the STORED subject — the privacy-masked address, not
    #      the raw one and not the /16-obscured form in the log line.
    #   2. `POST /api/colonel/ratelimit/reset` with kind=create_account_ip,
    #      which performs the delete AND records an AdminAuditEvent.
    #
    # Fail semantics mirror the other security limiters: Redis errors propagate
    # rather than silently permitting an unthrottled signup flood.
    #
    # Redis keys (string keys at the Redis boundary):
    #   - create_account:attempts:ip:{ip}  - per-IP request counter
    #   - create_account:locked:ip:{ip}    - per-IP lockout flag
    #
    # Config (site.authentication.create_account_rate_limit): enabled, max_per_ip,
    # window, lockout. Absent config -> enabled with the constant defaults below;
    # set enabled:false to disable (the test config does, so suite signups are not
    # throttled).
    #
    # Usage (both call sites above do exactly this — the simple-mode logic class
    # includes the module directly, the full-mode hook includes it into the
    # Rodauth class via auth_class_eval):
    #   include Onetime::Security::CreateAccountRateLimiter
    #   enforce_create_account_rate_limit!(client_ip) # before any account write
    module CreateAccountRateLimiter
      # Default signups permitted per window from a single masked client IP.
      #
      # Deliberately loose relative to what one PERSON needs (one signup, ever).
      # The bucket is a whole masked /24 — an office, a campus NAT, a coworking
      # space — and under the collapse condition above it can be the entire
      # deployment. A tight cap there would be an outage of the signup funnel,
      # i.e. worse than the LOW-severity spam it bounds. 10/hour still turns
      # unbounded account creation into a bounded, loggable, auditable trickle,
      # which is the whole ask of the finding.
      DEFAULT_MAX_PER_IP = 10

      # Default window in seconds over which signups are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Default lockout duration in seconds once the cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Audit verb recorded when the tier reaches its cap. Namespaced
      # `<resource>.<action>` like every other verb in the trail; the admin
      # console filters on the exact string, so it is a constant.
      AUDIT_VERB = 'auth.create_account_throttled'

      # Lua script that checks the lockout AND records the request in one atomic
      # round trip — same contract as {ResetRequestRateLimiter} and
      # {IncomingRateLimiter}: Redis serializes script executions, the increment
      # that reaches max_attempts sets the lockout flag and clears the counter,
      # and every later execution sees the flag and is denied before
      # incrementing, so concurrent bursts cannot overshoot the cap.
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

      # Enforce the account-creation rate limit and record this request. Raises
      # LimitExceeded when the IP is locked; a locked tier is never incremented
      # (the Lua script denies before INCR). No-op when the limiter is disabled
      # by config, and no-op when no client IP is available — see
      # create_account_ip_keys for why that skips rather than shares a bucket.
      #
      # @param client_ip [String, nil] The caller's edge-masked client IP.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_create_account_rate_limit!(client_ip)
        return unless create_account_rate_limit_enabled?
        return unless (keys = create_account_ip_keys(client_ip))

        allowed, detail = create_account_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [create_account_window, create_account_max_per_ip, create_account_lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            'Too many signup attempts. Please try again later.',
            retry_after: detail.to_i.positive? ? detail.to_i : create_account_lockout,
            max_attempts: create_account_max_per_ip,
          )
        end

        count = detail.to_i
        if count >= create_account_max_per_ip
          # This cap-reaching request was itself ALLOWED (the Lua script locks
          # after incrementing); the lockout applies to subsequent requests.
          obscured = obscured_create_account_ip(client_ip)
          OT.le "[CreateAccountRateLimiter] ip #{obscured} " \
                "hit cap (#{count}/#{create_account_max_per_ip}); " \
                "locked for #{create_account_lockout}s" \
                "#{collapsed_create_account_ip_hint}"
          record_create_account_throttle_audit(obscured, count)
        elsif count >= create_account_max_per_ip - 1
          OT.li "[CreateAccountRateLimiter] ip #{obscured_create_account_ip(client_ip)} " \
                "at #{count}/#{create_account_max_per_ip} signups"
        end
      end

      private

      # Write the queryable counterpart of the OT.le line above.
      #
      # SEPARATE RETENTION DOMAIN, and a BOUNDED WRITE FREQUENCY — both are
      # required, not stylistic. This is the SECOND unauthenticated writer into
      # the audit store, and the MAX_EVENTS rationale on
      # {Onetime::AdminAuditEvent} (rewritten when ResetRequestRateLimiter became
      # the first) requires any further unauthenticated-triggerable verb to carry
      # a comparable per-window bound or move to its own collection. This does
      # both:
      #
      #   - it writes to .record_security, whose security_events collection has
      #     its own count cap and age bound, NOT to .record, which holds the
      #     count-capped-with-no-TTL operator trail (purge, role change,
      #     suspension, impersonation) and would evict oldest-first under a
      #     flood;
      #   - it records ONLY on the cap-reaching request, never on the deny path,
      #     which an attacker can drive as fast as it can send. That bounds
      #     writes to one event per masked network per LOCKOUT window (default
      #     1h), so minting another costs a full cap's worth of requests from
      #     another masked network.
      #
      # Both properties are pinned by tests; keep them.
      #
      # The subject is the OBSCURED IP (/16), never the resolved one. Actor is
      # 'anonymous' — the caller is unauthenticated by construction on this
      # route, and normalize_actor would otherwise stamp 'unknown', which reads
      # as "we failed to resolve it" rather than "there is none".
      #
      # Best-effort, matching every other audit call site.
      def record_create_account_throttle_audit(obscured_ip, count)
        Onetime::AdminAuditEvent.record_security(
          actor: 'anonymous',
          verb: AUDIT_VERB,
          target: "ip:#{obscured_ip}",
          result: :failure,
          detail: {
            tier: 'ip',
            count: count,
            max_attempts: create_account_max_per_ip,
            window: create_account_window,
            lockout: create_account_lockout,
          },
        )
      rescue StandardError => ex
        # A signup must never fail because its audit event could not be
        # assembled.
        OT.le('[CreateAccountRateLimiter] audit record failed', exception: ex)
      end

      # Composite per-IP keys, or nil when no IP is available.
      #
      # Skipping is correct rather than fail-closed here: a blank suffix would
      # build ONE key shared by every IP-less caller, so the first few would lock
      # the bucket and every later one would be denied — a global signup outage
      # driven by whatever made the IP unresolvable. Same rationale as
      # LoginRateLimiter#login_ip_keys and ResetRequestRateLimiter's ip tier.
      # Unlike the reset limiter there is no second tier to fall back on, so this
      # is a genuine (small) hole: it needs the resolved client IP to be empty,
      # which in the mounted stack means IPPrivacyMiddleware did not run.
      def create_account_ip_keys(client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: "create_account:attempts:ip:#{client_ip}",
          lockout: "create_account:locked:ip:#{client_ip}",
        }
      end

      def create_account_rate_limit_config
        OT.conf.dig('site', 'authentication', 'create_account_rate_limit') || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config keeps
      # the protective default on; the test config disables it so suite signups
      # are not throttled.
      def create_account_rate_limit_enabled?
        create_account_rate_limit_config.fetch('enabled', true) != false
      end

      def create_account_max_per_ip
        positive_create_account_setting('max_per_ip', DEFAULT_MAX_PER_IP)
      end

      def create_account_window
        positive_create_account_setting('window', DEFAULT_WINDOW)
      end

      def create_account_lockout
        positive_create_account_setting('lockout', DEFAULT_LOCKOUT)
      end

      # Read a numeric setting, falling back to its default unless the configured
      # value coerces to a POSITIVE integer. A zero/garbage value (a typo'd env
      # var: `to_i` turns "abc" into 0) would otherwise invert enforcement — a
      # zero cap locks on the first request and a non-positive lockout makes the
      # Lua SETEX fail, turning every signup into a 500 instead of a throttle.
      def positive_create_account_setting(key, default)
        value = create_account_rate_limit_config[key].to_i
        value.positive? ? value : default
      end

      # Obscure the IP for logs: IPv4 keeps the /16, IPv6 is truncated to a short
      # prefix. The resolved value never reaches logs.
      def obscured_create_account_ip(client_ip)
        value = client_ip.to_s
        parts = value.split('.')
        return "#{parts[0]}.#{parts[1]}.x.x" if parts.length == 4

        value[0..8]
      end

      # Operator diagnostic appended to the lockout LOG LINE (server side only —
      # it never reaches a response body) when the deployment has not declared a
      # trusted reverse proxy, in which case the resolved client IP is
      # REMOTE_ADDR and every visitor shares one bucket. Self-contained on
      # purpose: it restates the condition and names both remedy env vars inline,
      # so an operator reading only the log line has the whole diagnosis. Keep it
      # that way — do not swap it for a doc pointer.
      #
      # Deliberately NOT a boot-time check: the same config is correct for a
      # direct-connect deployment and boot has no evidence a proxy exists, so a
      # boot warning would fire on every default install. A lockout is the first
      # moment the condition is actually demonstrated.
      def collapsed_create_account_ip_hint
        return '' if OT.conf.dig('site', 'network', 'trusted_proxy', 'enabled') == true

        '. NOTE: site.network.trusted_proxy is not enabled, so the client IP is ' \
          'REMOTE_ADDR; if this deployment is behind a reverse proxy every visitor ' \
          'shares this bucket and signup is blocked deployment-wide. Set ' \
          'TRUSTED_PROXY_ENABLED=true, or raise CREATE_ACCOUNT_RATE_LIMIT_MAX_PER_IP'
      end

      # Redis connection via the Customer model's dbclient — the subject is a
      # signup on the auth surface, so the counters live on the same shard as the
      # login/account rate-limit state (matches LoginRateLimiter and
      # ResetRequestRateLimiter).
      def create_account_redis
        Onetime::Customer.dbclient
      end
    end
  end
end
