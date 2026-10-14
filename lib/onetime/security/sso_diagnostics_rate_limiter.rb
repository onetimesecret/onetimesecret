# lib/onetime/security/sso_diagnostics_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/security/per_customer_rate_limit'

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
    # Per CUSTOMER, keyed on the public extid: one actor has one budget
    # whatever domain they point it at. The cap is small (10 per hour)
    # because a run is deterministic: the second run with the same stored
    # record says what the first did unless the record or the IdP changed.
    #
    # The mechanics (atomic Lua check-and-record, cap-reaching request
    # allowed, fail-closed on Redis errors, one security-trail event per
    # cap-hit) are {PerCustomerRateLimit}'s; this module declares the policy.
    # Charged from the END of RunDiagnostics#raise_concerns — after the
    # session, ownership and entitlement guards and after the stored record
    # is found — so a refused request costs nothing and the budget counts
    # runs that will actually contact the IdP.
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

      # Keep `kind` byte-identical with the 'sso_diagnostics' row of
      # Onetime::Operations::RateLimit::Registry::LIMITERS.
      POLICY = PerCustomerRateLimit::Policy.new(
        kind: 'sso_diagnostics',
        config_key: 'sso_diagnostics_rate_limit',
        default_max_per_customer: DEFAULT_MAX_PER_CUSTOMER,
        default_window: DEFAULT_WINDOW,
        default_lockout: DEFAULT_LOCKOUT,
        audit_verb: AUDIT_VERB,
        message: 'Too many saved-configuration checks. Please try again later.',
        log_tag: 'SsoDiagnosticsRateLimiter',
        action_noun: 'runs',
      )

      # Enforce the per-customer run limit and record this run. See
      # {PerCustomerRateLimit.enforce!}.
      #
      # @param customer_extid [String] The acting customer's public id.
      # @raise [ArgumentError] If the subject is blank.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_sso_diagnostics_rate_limit!(customer_extid)
        PerCustomerRateLimit.enforce!(POLICY, customer_extid)
      end

      private

      # Read-only views of the policy's settings, for callers and tryouts.
      # enforce! reads PerCustomerRateLimit directly, so stubbing one of these
      # on an including object does not change enforcement.
      def sso_diagnostics_redis = PerCustomerRateLimit.redis

      def sso_diagnostics_rate_limit_enabled? = PerCustomerRateLimit.enabled?(POLICY)

      def sso_diagnostics_max_per_customer = PerCustomerRateLimit.max_per_customer(POLICY)

      def sso_diagnostics_window = PerCustomerRateLimit.window(POLICY)

      def sso_diagnostics_lockout = PerCustomerRateLimit.lockout(POLICY)
    end
  end
end
