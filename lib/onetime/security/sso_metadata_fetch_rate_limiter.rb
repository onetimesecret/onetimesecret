# lib/onetime/security/sso_metadata_fetch_rate_limiter.rb
#
# frozen_string_literal: true

require 'onetime/security/per_customer_rate_limit'

module Onetime
  module Security
    # SsoMetadataFetchRateLimiter - Bounds "Fetch from metadata" requests
    #
    # POST /api/domains/:extid/sso/metadata (DomainsAPI::Logic::SsoConfig::
    # FetchIdpMetadata) makes one outbound HTTPS request per call, to a host
    # the CALLER chooses (the SAML IdP metadata URL in the request body),
    # through the SSRF-guarded DiscoveryFetcher. Nothing stored is sent and
    # the response is the public metadata document's own content, so there
    # is no oracle to protect; what this bounds is EGRESS VOLUME. The
    # endpoint is session-authenticated and limited to the organization
    # owner, but a leaked owner session could otherwise point this
    # application at any public host in a loop.
    #
    # Per CUSTOMER, keyed on the public extid: one actor has one budget
    # whatever domain they point it at. Thirty per hour is generous for an
    # admin iterating on a URL (wrong tenant, missing ?appid=, a typo) and
    # small next to what a loop needs to matter.
    #
    # The mechanics (atomic Lua check-and-record, cap-reaching request
    # allowed, fail-closed on Redis errors, one security-trail event per
    # cap-hit) are {PerCustomerRateLimit}'s; this module declares the policy.
    # Charged from the END of FetchIdpMetadata#raise_concerns — after the
    # session, ownership and entitlement guards, the install-wide SAML
    # switch and the presence of a metadata URL — so a request those refuse
    # costs nothing. A URL refused later, by the structural or SSRF host
    # check in #process, IS charged: that host check resolves the
    # caller-chosen hostname, so the budget bounds DNS lookups as well as
    # fetches.
    #
    # CLEARING A STUCK LOCKOUT — the same two paths as every other limiter,
    # over kind `sso_metadata_fetch`:
    #
    #   1. `bin/ots ratelimit keys sso_metadata_fetch <extid>` piped to
    #      valkey-cli (the CLI only PRINTS commands; see ratelimit_command.rb).
    #   2. `POST /api/colonel/ratelimit/reset` with kind=sso_metadata_fetch,
    #      which performs the delete AND records a ColonelAuditEvent.
    #
    # Redis keys (string keys at the Redis boundary; Customer shard):
    #   - sso_metadata_fetch:attempts:{extid}  - per-customer fetch counter
    #   - sso_metadata_fetch:locked:{extid}    - per-customer lockout flag
    #
    # Config (features.organizations.sso_metadata_fetch_rate_limit): enabled,
    # max_per_customer, window, lockout. Absent config -> enabled with the
    # constant defaults below; set enabled:false to disable (the test config
    # does, so the endpoint specs, which run many examples as one owner, are
    # not throttled; the endpoint spec enables it in-process for its
    # rate-limit example).
    #
    # Usage:
    #   include Onetime::Security::SsoMetadataFetchRateLimiter
    #   enforce_sso_metadata_fetch_rate_limit!(cust.extid)  # last line of raise_concerns
    module SsoMetadataFetchRateLimiter
      # Fetches permitted per window for one customer.
      DEFAULT_MAX_PER_CUSTOMER = 30

      # Window in seconds over which fetches are counted (1 hour).
      DEFAULT_WINDOW = 3600

      # Lockout duration in seconds once the cap is hit (1 hour).
      DEFAULT_LOCKOUT = 3600

      # Audit verb recorded when the bucket reaches its cap. Namespaced
      # `<resource>.<action>` like every other verb in the trail.
      AUDIT_VERB = 'sso.metadata_fetch_throttled'

      # Keep `kind` byte-identical with the 'sso_metadata_fetch' row of
      # Onetime::Operations::RateLimit::Registry::LIMITERS.
      POLICY = PerCustomerRateLimit::Policy.new(
        kind: 'sso_metadata_fetch',
        config_key: 'sso_metadata_fetch_rate_limit',
        default_max_per_customer: DEFAULT_MAX_PER_CUSTOMER,
        default_window: DEFAULT_WINDOW,
        default_lockout: DEFAULT_LOCKOUT,
        audit_verb: AUDIT_VERB,
        message: 'Too many metadata fetches. Please try again later.',
        log_tag: 'SsoMetadataFetchRateLimiter',
        action_noun: 'fetches',
      )

      # Enforce the per-customer fetch limit and record this fetch. See
      # {PerCustomerRateLimit.enforce!}.
      #
      # @param customer_extid [String] The acting customer's public id.
      # @raise [ArgumentError] If the subject is blank.
      # @raise [Onetime::LimitExceeded] If the limit is exceeded.
      # @return [void]
      def enforce_sso_metadata_fetch_rate_limit!(customer_extid)
        PerCustomerRateLimit.enforce!(POLICY, customer_extid)
      end

      private

      # Read-only views of the policy's settings, for callers and specs.
      # enforce! reads PerCustomerRateLimit directly, so stubbing one of these
      # on an including object does not change enforcement.
      def sso_metadata_fetch_redis = PerCustomerRateLimit.redis

      def sso_metadata_fetch_rate_limit_enabled? = PerCustomerRateLimit.enabled?(POLICY)

      def sso_metadata_fetch_max_per_customer = PerCustomerRateLimit.max_per_customer(POLICY)

      def sso_metadata_fetch_window = PerCustomerRateLimit.window(POLICY)

      def sso_metadata_fetch_lockout = PerCustomerRateLimit.lockout(POLICY)
    end
  end
end
