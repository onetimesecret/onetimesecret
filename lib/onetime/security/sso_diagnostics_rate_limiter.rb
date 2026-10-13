# lib/onetime/security/sso_diagnostics_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'

module Onetime
  module Security
    # SsoDiagnosticsRateLimiter - Bounds "Check saved configuration" runs
    #
    # POST /api/domains/:extid/sso/diagnostics (DomainsAPI::Logic::SsoConfig::
    # RunDiagnostics) is the one customer-facing endpoint that sends a STORED
    # credential to a third party: for an Entra ID record every run makes a
    # client-credentials token request to login.microsoftonline.com with the
    # saved client secret, and for oidc / entra_id every run fetches the IdP's
    # discovery document. The endpoint is session-authenticated and limited
    # to the organization owner, so the caller is accountable; what this
    # bounds is VOLUME, for two reasons:
    #
    #   - a loop of runs with a wrong secret is a loop of failed token
    #     requests against the customer's app registration, which Entra
    #     throttles on its own terms (and which shows up in the customer's
    #     sign-in logs as repeated AADSTS7000215);
    #   - a leaked owner session could otherwise use the endpoint as an
    #     unbounded oracle for whether the stored secret is still accepted.
    #
    # KEYED ON cust.extid, the acting customer's PUBLIC id — the same value
    # every logic class returns as user_id and the audit trail records as
    # actor. Per CUSTOMER rather than per domain: the thing being bounded is
    # one actor's run volume, and a per-domain bucket would hand an owner
    # with several domains a fresh budget per domain while a second owner of
    # the same domain would share one. Per customer, one actor has one
    # budget whatever they point it at. The cap is small (10 per hour) because
    # a run is deterministic: the second run with the same stored record
    # says what the first did unless the record or the IdP changed.
    #
    # Same contract as {CreateAccountRateLimiter}: one atomic Lua round trip
    # checks the lockout and records the request; the request that reaches
    # the cap is itself ALLOWED and sets the lockout; later requests are
    # denied before incrementing. Charged from the END of
    # RunDiagnostics#raise_concerns — after the session, ownership and
    # entitlement guards and after the stored record is found — so a refused
    # request costs nothing and the budget counts runs that will actually
    # contact the IdP.
    #
    # NEVER interpolate a session id — Rack aliases SessionId#to_s to the live
    # bearer cookie (#4330). The extid is a public identifier.
    #
    # Fail-closed on Redis errors, like every sibling limiter: an outage 500s
    # a diagnostics run rather than admitting an unthrottled one.
    #
    # CLEARING A STUCK LOCKOUT — the same two paths as every other limiter,
    # over kind `sso_diagnostics`:
    #
    #   1. `bin/ots ratelimit keys sso_diagnostics <extid>` piped to
    #      valkey-cli (the CLI only PRINTS commands; see ratelimit_command.rb).
    #   2. `POST /api/colonel/ratelimit/reset` with kind=sso_diagnostics,
    #      which performs the delete AND records a ColonelAuditEvent.
    #
    # Redis keys (string keys at the Redis boundary; Customer shard):
    #   - sso_diagnostics:attempts:{extid}  - per-customer run counter
    #   - sso_diagnostics:locked:{extid}    - per-customer lockout flag
    #
    # Config (features.organizations.sso_diagnostics_rate_limit): enabled,
    # max_per_customer, window, lockout. Absent config -> enabled with the
    # constant defaults below; set enabled:false to disable (the test config
    # does, so the diagnostics specs, which run many examples as one owner,
    # are not throttled; the limiter tryout enables it in-process).
    #
    # Usage:
    #   include Onetime::Security::SsoDiagnosticsRateLimiter
    #   enforce_sso_diagnostics_rate_limit!(cust.extid)  # last line of raise_concerns
    module SsoDiagnosticsRateLimiter
      # Runs permitted per window for one customer. Ten is several full
      # edit-save-check cycles in an hour, and well under what a scripted
      # loop needs to be useful as an oracle.
      DEFAULT_MAX_PER_CUSTOMER = 10

      # Window in seconds over which runs are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Lockout duration in seconds once the cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Audit verb recorded when the bucket reaches its cap. Namespaced
      # `<resource>.<action>` like every other verb in the trail.
      AUDIT_VERB = 'sso.diagnostics_throttled'

      # Lua script that checks the lockout AND records the request in one
      # atomic round trip — byte-identical in contract to
      # {CreateAccountRateLimiter::CHECK_AND_RECORD_SCRIPT}: the increment
      # that reaches max_attempts sets the lockout flag and clears the
      # counter, and every later execution sees the flag and is denied before
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

      # Enforce the per-customer run limit and record this run. Raises
      # LimitExceeded when the customer is locked; a locked bucket is never
      # incremented (the Lua script denies before INCR). No-op when the
      # limiter is disabled by config. A blank subject is refused rather than
      # skipped: the call site has already required an authenticated customer,
      # so a missing extid is a programming error, and a shared blank-key
      # bucket would lock every such caller out together.
      #
      # @param customer_extid [String] The acting customer's public id.
      # @raise [ArgumentError] If the subject is blank.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_sso_diagnostics_rate_limit!(customer_extid)
        return unless sso_diagnostics_rate_limit_enabled?

        subject = customer_extid.to_s
        raise ArgumentError, 'SsoDiagnosticsRateLimiter needs a customer extid' if subject.empty?

        keys            = sso_diagnostics_keys(subject)
        allowed, detail = sso_diagnostics_redis.eval(
          CHECK_AND_RECORD_SCRIPT,
          keys: [keys[:attempts], keys[:lockout]],
          argv: [sso_diagnostics_window, sso_diagnostics_max_per_customer, sso_diagnostics_lockout],
        )

        if allowed.to_i != 1
          raise Onetime::LimitExceeded.new(
            'Too many saved-configuration checks. Please try again later.',
            retry_after: detail.to_i.positive? ? detail.to_i : sso_diagnostics_lockout,
            max_attempts: sso_diagnostics_max_per_customer,
          )
        end

        count = detail.to_i
        if count >= sso_diagnostics_max_per_customer
          # This cap-reaching run was itself ALLOWED (the Lua script locks after
          # incrementing); the lockout applies to the next one.
          OT.le "[SsoDiagnosticsRateLimiter] customer #{subject} hit cap " \
                "(#{count}/#{sso_diagnostics_max_per_customer}); locked for #{sso_diagnostics_lockout}s"
          record_sso_diagnostics_throttle_audit(subject, count)
        elsif count >= sso_diagnostics_max_per_customer - 2
          OT.li "[SsoDiagnosticsRateLimiter] customer #{subject} at #{count}/#{sso_diagnostics_max_per_customer} runs"
        end
      end

      private

      # Cap-reaching run only — one event per customer per lockout window —
      # in the SECURITY trail (count-capped with an age bound), never the
      # operator trail. Best-effort, matching every other audit call site: a
      # throttle must never fail because its event could not be assembled.
      def record_sso_diagnostics_throttle_audit(subject, count)
        Onetime::ColonelAuditEvent.record_security(
          actor: subject,
          verb: AUDIT_VERB,
          target: subject,
          result: :failure,
          detail: {
            count: count,
            max_attempts: sso_diagnostics_max_per_customer,
            window: sso_diagnostics_window,
            lockout: sso_diagnostics_lockout,
          },
        )
      rescue StandardError => ex
        OT.le('[SsoDiagnosticsRateLimiter] audit record failed', exception: ex)
      end

      # Keep byte-identical with the 'sso_diagnostics' row of
      # Onetime::Operations::RateLimit::Registry::LIMITERS, or the CLI,
      # Inspect and Reset cannot see the keys.
      def sso_diagnostics_keys(subject)
        {
          attempts: "sso_diagnostics:attempts:#{subject}",
          lockout: "sso_diagnostics:locked:#{subject}",
        }
      end

      # Co-located with the Customer shard because the subject is a Customer
      # extid (matches login / reset / create_account / colonel).
      def sso_diagnostics_redis
        Onetime::Customer.dbclient
      end

      def sso_diagnostics_rate_limit_config
        OT.conf.dig('features', 'organizations', 'sso_diagnostics_rate_limit') || {}
      end

      # Enabled unless config explicitly sets enabled:false. Absent config
      # keeps the protective default on.
      def sso_diagnostics_rate_limit_enabled?
        sso_diagnostics_rate_limit_config.fetch('enabled', true) != false
      end

      def sso_diagnostics_max_per_customer
        positive_sso_diagnostics_setting('max_per_customer', DEFAULT_MAX_PER_CUSTOMER)
      end

      def sso_diagnostics_window
        positive_sso_diagnostics_setting('window', DEFAULT_WINDOW)
      end

      def sso_diagnostics_lockout
        positive_sso_diagnostics_setting('lockout', DEFAULT_LOCKOUT)
      end

      # Fall back to the default unless the configured value coerces to a
      # POSITIVE integer. A zero or garbage value would otherwise invert
      # enforcement: a zero cap locks on the first run, and a non-positive
      # lockout makes the Lua SETEX fail, turning every run into a 500.
      def positive_sso_diagnostics_setting(key, default)
        value = sso_diagnostics_rate_limit_config[key].to_i
        value.positive? ? value : default
      end
    end
  end
end
