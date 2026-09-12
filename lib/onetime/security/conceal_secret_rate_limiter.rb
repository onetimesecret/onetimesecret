# lib/onetime/security/conceal_secret_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  module Security
    # ConcealSecretRateLimiter - Throttles unauthenticated secret creation
    #
    # Closes finding F-02 (2026-08-14 audit): the secret-creation path had no
    # limiter of any kind on the modern API surface. The reachable primitive is
    # unauthenticated, unthrottled secret creation — one Receipt + one Secret
    # record per request, each carrying anonymous-lifetime TTL. A single
    # anonymous client sustained ~113 req/s at ~18 KiB of Redis per secret,
    # writing ~1 GiB of Redis in ~8.6 minutes. Because Redis also holds sessions,
    # that is a full-outage DoS reachable by any stranger with `curl`.
    #
    # Enforced on the anonymous secret-creation paths, ahead of the
    # Receipt.spawn_pair write:
    #
    #   - V2/V3 API (conceal AND generate): the shared
    #     V2::Logic::Secrets::BaseSecretAction#raise_concerns, which every conceal
    #     and generate logic class inherits (V3 subclasses V2), keyed on the
    #     edge-masked client IP the auth strategy resolved;
    #   - V1 API (share/generate/create): the controller
    #     (apps/api/v1/controllers), whose own return-based error convention wraps
    #     the raise — V1 logic never receives a strategy_result, so the masked IP
    #     is read from env['otto.client_ip'] there instead.
    #
    # Both take their subject from the same edge-masked address
    # (env['otto.client_ip'], surfaced as strategy_result.metadata[:ip] in the
    # mounted stack), so the keyspace and any operator remediation are identical
    # across API versions. Keep the call sites in lockstep on the subject passed.
    #
    # ANONYMOUS ONLY. The cap is charged to guest requests alone. An
    # authenticated caller is accountable through their Customer record and plan
    # limits, is the legitimate high-volume creator (bulk API integrations), and
    # was never the DoS this bounds — charging them would risk a false lockout of
    # the core product function for exactly the users least likely to be abusing
    # it. The finding is an UNauthenticated flood, so the gate is `anonymous?`.
    #
    # SINGLE TIER, IP ONLY. Secret creation holds nothing else fixed the way the
    # reset-request limiter holds an email fixed: an anonymous conceal carries no
    # account-derived identifier to key on, and keying on the secret body would
    # both mint one bucket per request (capping nothing) and hash attacker-chosen
    # bytes. Capping volume per origin is the whole of the available defense.
    #
    # IP GRANULARITY, and the COLLAPSE CONDITION, are identical to
    # {CreateAccountRateLimiter}: the subject is the privacy-masked network (/24
    # IPv4, /48 IPv6) the universal IPPrivacyMiddleware resolved, so the bucket is
    # shared by that neighborhood; and with site.network.trusted_proxy disabled
    # behind a reverse proxy the resolved IP is the PROXY's address for every
    # request, collapsing the whole deployment into one bucket. The default cap is
    # deliberately loose because of this, and the lockout log line appends the
    # same self-contained operator hint.
    #
    # CLEARING A STUCK LOCKOUT — same two paths as every other limiter, over kind
    # `create_secret`:
    #
    #   1. `bin/ots ratelimit keys create_secret <masked-ip>` piped to valkey-cli
    #      (the CLI only PRINTS commands; see ratelimit_command.rb). <masked-ip>
    #      is the STORED subject — the privacy-masked address, not the raw one and
    #      not the /16-obscured form in the log line.
    #   2. `POST /api/colonel/ratelimit/reset` with kind=create_secret, which
    #      performs the delete AND records a ColonelAuditEvent.
    #
    # Fail semantics mirror the other security limiters: Redis errors propagate
    # rather than silently permitting an unthrottled creation flood.
    #
    # Redis keys (string keys at the Redis boundary):
    #   - create_secret:attempts:ip:{ip}  - per-IP request counter
    #   - create_secret:locked:ip:{ip}    - per-IP lockout flag
    #
    # Config (site.secret_options.create_rate_limit): enabled, max_per_ip, window,
    # lockout. Absent config -> enabled with the constant defaults below; set
    # enabled:false to disable (the test config does, so suite secret creation is
    # not throttled).
    #
    # Usage:
    #   include Onetime::Security::ConcealSecretRateLimiter
    #   enforce_conceal_secret_rate_limit!(client_ip) # before any secret write
    module ConcealSecretRateLimiter
      # Default anonymous secret creations permitted per window from a single
      # masked client IP.
      #
      # Ten times the sibling perimeter limiters (create_account / reset =
      # 10/hour) because secret creation is the core product action, not a rare
      # one — a shared masked /24 (office, campus NAT) legitimately conceals far
      # more secrets per hour than it signs up accounts. Still, 500/hour turns the
      # measured ~1 GiB-in-8.6-minutes flood (~57k secrets) into at most ~500
      # secrets (~9 MiB) per masked network per window before the tier locks:
      # unbounded storage growth becomes a bounded, loggable, auditable trickle,
      # which is the whole ask of the finding. Raise it for dense-NAT populations
      # (SECRET_CREATE_RATE_LIMIT_MAX_PER_IP); a too-tight value here would be an
      # outage of secret creation for a whole neighborhood.
      DEFAULT_MAX_PER_IP = 500

      # Default window in seconds over which creations are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Default lockout duration in seconds once the cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Audit verb recorded when the tier reaches its cap. Namespaced
      # `<resource>.<action>` like every other verb in the trail; the admin
      # console filters on the exact string, so it is a constant.
      AUDIT_VERB = 'secrets.create_throttled'

      # Lua script that checks the lockout AND records the request in one atomic
      # round trip — same contract as {CreateAccountRateLimiter}: Redis serializes
      # script executions, the increment that reaches max_attempts sets the
      # lockout flag and clears the counter, and every later execution sees the
      # flag and is denied before incrementing, so concurrent bursts cannot
      # overshoot the cap. Returns {1, current_count} when allowed, {0,
      # lockout_ttl} when denied.
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

      # Enforce the secret-creation rate limit and record this request. Raises
      # LimitExceeded when the IP is locked; a locked tier is never incremented
      # (the Lua script denies before INCR). No-op when the limiter is disabled by
      # config, and no-op when no client IP is available — see
      # conceal_secret_ip_keys for why that skips rather than shares a bucket.
      #
      # The caller decides WHO is charged (the call sites gate on anonymous?);
      # this method is subject-agnostic so the same code path serves every entry.
      #
      # @param client_ip [String, nil] The caller's edge-masked client IP.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_conceal_secret_rate_limit!(client_ip)
        return unless conceal_secret_rate_limit_enabled?
        return unless (keys = conceal_secret_ip_keys(client_ip))

        allowed, detail = conceal_secret_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [conceal_secret_window, conceal_secret_max_per_ip, conceal_secret_lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            'Too many secrets created. Please try again later.',
            retry_after: detail.to_i.positive? ? detail.to_i : conceal_secret_lockout,
            max_attempts: conceal_secret_max_per_ip,
          )
        end

        count = detail.to_i
        if count >= conceal_secret_max_per_ip
          # This cap-reaching request was itself ALLOWED (the Lua script locks
          # after incrementing); the lockout applies to subsequent requests.
          obscured = obscured_conceal_secret_ip(client_ip)
          OT.le "[ConcealSecretRateLimiter] ip #{obscured} " \
                "hit cap (#{count}/#{conceal_secret_max_per_ip}); " \
                "locked for #{conceal_secret_lockout}s" \
                "#{collapsed_conceal_secret_ip_hint}"
          record_conceal_secret_throttle_audit(obscured, count)
        elsif count >= conceal_secret_max_per_ip - 1
          OT.li "[ConcealSecretRateLimiter] ip #{obscured_conceal_secret_ip(client_ip)} " \
                "at #{count}/#{conceal_secret_max_per_ip} creations"
        end
      end

      private

      # Write the queryable counterpart of the OT.le line above.
      #
      # Same discipline as {CreateAccountRateLimiter}: an unauthenticated-
      # triggerable verb must bound its own write frequency and stay out of the
      # count-capped-with-no-TTL operator trail. This writes to .record_security
      # (its own count cap and age bound), and ONLY on the cap-reaching request,
      # never on the deny path an attacker can drive as fast as it can send — so
      # writes are bounded to one event per masked network per lockout window.
      #
      # The subject is the OBSCURED IP (/16), never the resolved one. Actor is
      # 'anonymous' — the caller is unauthenticated by construction on this path.
      # Best-effort, matching every other audit call site.
      def record_conceal_secret_throttle_audit(obscured_ip, count)
        Onetime::ColonelAuditEvent.record_security(
          actor: 'anonymous',
          verb: AUDIT_VERB,
          target: "ip:#{obscured_ip}",
          result: :failure,
          detail: {
            tier: 'ip',
            count: count,
            max_attempts: conceal_secret_max_per_ip,
            window: conceal_secret_window,
            lockout: conceal_secret_lockout,
          },
        )
      rescue StandardError => ex
        # Secret creation must never fail because its audit event could not be
        # assembled.
        OT.le('[ConcealSecretRateLimiter] audit record failed', exception: ex)
      end

      # Composite per-IP keys, or nil when no IP is available.
      #
      # Skipping is correct rather than fail-closed here: a blank suffix would
      # build ONE key shared by every IP-less caller, so the first few would lock
      # the bucket and every later one would be denied — a global creation outage
      # driven by whatever made the IP unresolvable. Same rationale as
      # CreateAccountRateLimiter#create_account_ip_keys.
      def conceal_secret_ip_keys(client_ip)
        return nil if client_ip.to_s.empty?

        {
          attempts: "create_secret:attempts:ip:#{client_ip}",
          lockout: "create_secret:locked:ip:#{client_ip}",
        }
      end

      def conceal_secret_rate_limit_config
        OT.conf.dig('site', 'secret_options', 'create_rate_limit') || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config keeps
      # the protective default on; the test config disables it so suite secret
      # creation is not throttled.
      def conceal_secret_rate_limit_enabled?
        conceal_secret_rate_limit_config.fetch('enabled', true) != false
      end

      def conceal_secret_max_per_ip
        positive_conceal_secret_setting('max_per_ip', DEFAULT_MAX_PER_IP)
      end

      def conceal_secret_window
        positive_conceal_secret_setting('window', DEFAULT_WINDOW)
      end

      def conceal_secret_lockout
        positive_conceal_secret_setting('lockout', DEFAULT_LOCKOUT)
      end

      # Read a numeric setting, falling back to its default unless the configured
      # value coerces to a POSITIVE integer. A zero/garbage value (a typo'd env
      # var: `to_i` turns "abc" into 0) would otherwise invert enforcement — a
      # zero cap locks on the first request and a non-positive lockout makes the
      # Lua SETEX fail, turning every creation into a 500 instead of a throttle.
      def positive_conceal_secret_setting(key, default)
        value = conceal_secret_rate_limit_config[key].to_i
        value.positive? ? value : default
      end

      # Obscure the IP for logs: IPv4 keeps the /16, IPv6 is truncated to a short
      # prefix. The resolved value never reaches logs.
      def obscured_conceal_secret_ip(client_ip)
        value = client_ip.to_s
        parts = value.split('.')
        return "#{parts[0]}.#{parts[1]}.x.x" if parts.length == 4

        value[0..8]
      end

      # Operator diagnostic appended to the lockout LOG LINE (server side only —
      # it never reaches a response body) when the deployment has not declared a
      # trusted reverse proxy, in which case the resolved client IP is REMOTE_ADDR
      # and every visitor shares one bucket. Self-contained on purpose: it
      # restates the condition and names both remedy env vars inline, so an
      # operator reading only the log line has the whole diagnosis.
      #
      # Read through the shared predicate rather than digging the config here, so
      # the hint asks the same question the IP-privacy mount asked (#4087). No
      # require_relative — this file is reached via `require 'onetime'`, which
      # loads the middleware stack, and the constant resolves at call time.
      def collapsed_conceal_secret_ip_hint
        return '' if Onetime::Application::MiddlewareStack.trusted_proxy_enabled?

        '. NOTE: site.network.trusted_proxy is not enabled, so the client IP is ' \
          'REMOTE_ADDR; if this deployment is behind a reverse proxy every visitor ' \
          'shares this bucket and secret creation is blocked deployment-wide. Set ' \
          'TRUSTED_PROXY_ENABLED=true, or raise SECRET_CREATE_RATE_LIMIT_MAX_PER_IP'
      end

      # Redis connection via the Secret model's dbclient — the counters live on
      # the same shard as the secrets themselves (matches the passphrase and
      # invite limiters in the ratelimit Registry).
      def conceal_secret_redis
        Onetime::Secret.dbclient
      end
    end
  end
end
