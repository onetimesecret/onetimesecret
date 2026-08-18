# lib/onetime/models/custom_domain/sso_config.rb
#
# frozen_string_literal: true

require_relative '../features/boolean_encoding'

#
# CustomDomain::SsoConfig - Per-domain SSO credential storage
#
# This model stores SSO credentials bound to a specific CustomDomain.
# This enables multi-IdP configurations where different domains owned
# by the same organization can use different identity providers.
#
# Use Cases:
#   - Regional compliance: secrets.acme.eu uses a regional OIDC IdP, secrets.acme.com uses Entra ID
#   - Gradual rollout: enable SSO on one domain before expanding to others
#   - Subsidiary isolation: different business units use different IdPs
#
# Credential Binding:
#   Credentials are encrypted with AAD (Additional Authenticated Data) bound
#   to domain_id, preventing credential swapping attacks between domains.
#
# See: apps/web/auth/config/hooks/omniauth_tenant.rb (tenant resolution)
#
module Onetime
  class CustomDomain < Familia::Horreum
    class SsoConfig < Familia::Horreum
      include Familia::Features::Autoloader

      SCHEMA = 'models/domain-sso-config'

      # Supported SSO provider types.
      #
      # Tenant SSO is OIDC/Entra-only by design (#3902). Identity partitioning
      # is keyed (provider, issuer, uid), so a tenant provider must resolve a
      # tenant-distinguishing issuer. GitHub (plain OAuth2, no issuer) and
      # Google (single GLOBAL issuer accounts.google.com) both resolve to the
      # shared '' sentinel, which cannot partition identities per tenant —
      # their callbacks are refused on tenant surfaces (PR #3900,
      # refuse_issuerless_on_tenant?), so they are not configurable here.
      # PLATFORM/install-level SSO still supports them (separate surface,
      # registered from ENV in apps/web/auth/config/features/omniauth.rb).
      PROVIDER_TYPES = %w[oidc entra_id].freeze

      # Provider metadata for UI filtering logic
      #
      # :requires_domain_filter - When true, UI should show domain filter config
      #   prominently because the IdP doesn't restrict access by default.
      #   When false, IdP controls access via user/app assignment.
      #
      # :idp_controls_access - When true, the IdP is the source of truth for
      #   which users can access the app. When false, anyone with valid IdP
      #   credentials could potentially authenticate.
      #
      PROVIDER_METADATA = {
        'oidc' => {
          requires_domain_filter: true,
          idp_controls_access: false,
          description: 'Generic OpenID Connect provider - domain filtering recommended',
        },
        'entra_id' => {
          requires_domain_filter: false,
          idp_controls_access: true,
          description: 'Microsoft Entra ID - access controlled via Azure app assignment',
        },
      }.freeze

      # Map provider_type to platform route name ENV var and default.
      # Must match platform registration in omniauth.rb.
      # Tenant requests reuse platform-registered strategies, so the
      # route_name sent to frontend must match the registered route.
      PROVIDER_ROUTE_MAP = {
        'oidc' => { env_var: 'OIDC_ROUTE_NAME', default: 'oidc' },
        'entra_id' => { env_var: 'ENTRA_ROUTE_NAME', default: 'entra' },
      }.freeze

      prefix :custom_domain__sso_config

      feature :encrypted_fields

      # domain_id is the CustomDomain's identifier (objid), used as our key.
      # This creates a 1:1 relationship: one SSO config per domain.
      identifier_field :domain_id
      field :domain_id

      # Core configuration fields
      field :provider_type   # One of PROVIDER_TYPES
      field :enabled         # Boolean string ('true'/'false')
      field :display_name    # Human-readable name for UI

      # Provider-specific fields
      #
      # Required fields vary by provider_type:
      #   - entra_id: requires tenant_id
      #   - oidc:     requires issuer
      #
      # Both remaining providers carry a tenant-distinguishing issuer — the
      # reason issuerless OAuth2 providers were removed from this surface
      # (#3902, see PROVIDER_TYPES).
      #
      # Universal required fields (all providers):
      #   - client_id, provider_type
      # client_secret is required for entra_id only — OIDC public clients
      # (PKCE) may omit it. display_name is optional.
      #
      # See: validation_errors method for enforcement
      #
      field :tenant_id       # Entra ID: Azure AD tenant ID (required for entra_id only)
      field :issuer          # OIDC: Issuer URL for discovery (required for oidc only)

      # Encrypted credential storage with domain-bound AAD
      encrypted_field :client_id, aad_fields: [:domain_id]
      encrypted_field :client_secret, aad_fields: [:domain_id]

      # Domain allowlist (JSON array string)
      field :allowed_domains_json

      # Timestamps (Unix epoch integers)
      field :created
      field :updated

      # Enforcement settings
      field :enforce_sso_only  # Boolean string ('true'/'false')
      field :grant_org_scope   # Boolean string ('true'/'false')

      # Field encoding specs consumed by the boolean_encoding feature (below)
      # and the registry's load-time setter check. SSO is not colonel-editable
      # (ConfigRegistry KINDS `editable: false`), so these do not enter the
      # registry's composed FIELD_SPECS (#3951).
      FIELD_SPECS = {
        'enabled' => { type: :boolean, storage: :string },
        'enforce_sso_only' => { type: :boolean, storage: :string },
        'grant_org_scope' => { type: :boolean, storage: :string },
      }.freeze

      # Tolerant predicates + normalizing setters for the boolean fields in
      # FIELD_SPECS above (#3951). Must come after both the field
      # declarations and the constant.
      feature :boolean_encoding

      def init
        self.enabled          ||= 'false'
        self.provider_type    ||= 'oidc'
        self.enforce_sso_only ||= 'false'
        self.grant_org_scope  ||= 'false'
      end

      # Returns metadata for the current provider type.
      #
      # @return [Hash] Provider metadata
      def provider_metadata
        PROVIDER_METADATA.fetch(provider_type, {})
      end

      # Whether domain filtering is recommended for this provider.
      #
      # @return [Boolean]
      def requires_domain_filter?
        provider_metadata.fetch(:requires_domain_filter, false)
      end

      # Whether the IdP controls access via user/app assignment.
      #
      # @return [Boolean]
      def idp_controls_access?
        provider_metadata.fetch(:idp_controls_access, true)
      end

      # Returns the platform route name for this provider.
      #
      # Tenant requests reuse platform-registered OmniAuth strategies.
      # This method resolves the route name that matches the platform's
      # registered route, ensuring the frontend constructs valid URLs.
      #
      # The route name is determined by ENV vars (e.g., ENTRA_ROUTE_NAME)
      # that control platform strategy registration in omniauth.rb.
      #
      # @return [String] Platform route name (e.g., 'entra' for entra_id)
      def platform_route_name
        mapping = PROVIDER_ROUTE_MAP[provider_type]
        return provider_type unless mapping

        ENV.fetch(mapping[:env_var], mapping[:default])
      end

      # Enable SSO for this domain.
      # @return [void]
      def enable!
        self.enabled = 'true'
        save
      end

      # Disable SSO for this domain.
      # @return [void]
      def disable!
        self.enabled = 'false'
        save
      end

      # Get the list of allowed email domains.
      #
      # @return [Array<String>] Lowercase domain names
      def allowed_domains
        return [] if allowed_domains_json.to_s.empty?

        JSON.parse(allowed_domains_json)
      rescue JSON::ParserError
        []
      end

      # Set the list of allowed email domains.
      #
      # Validates each domain using PublicSuffix to ensure it has a valid TLD.
      # Supports internationalized domain names (IDN).
      #
      # @param domains [Array<String>] Domain names to allow
      # @return [void]
      # @raise [Onetime::Problem] if any domain is invalid
      def allowed_domains=(domains)
        normalized = Array(domains).map { it.to_s.strip.downcase }.uniq.reject(&:empty?)

        # Validate each domain using PublicSuffix (handles IDN, validates TLD)
        normalized.each do |domain|
          Utils::DomainParser.cached_parse(domain)
        rescue PublicSuffix::Error => ex
          raise Onetime::Problem, "Invalid domain: #{domain} (#{ex.message})"
        end

        self.allowed_domains_json = normalized.empty? ? nil : JSON.generate(normalized)
      end

      # Whether allowed_domains_json holds something we cannot read as a
      # domain list.
      #
      # allowed_domains (above) swallows JSON::ParserError and returns [], and
      # valid_email_domain? reads an empty list as "no allowlist configured →
      # allow all". That pairing is right for display surfaces — a corrupt
      # value must not 500 the config UI — but on the AUTHENTICATION path it
      # inverts the operator's intent: a hand-edited or truncated value would
      # silently disable the very restriction it encodes. Callers that gate
      # sign-in consult this first and deny when it is true, so a value we
      # cannot parse fails closed instead of opening the door.
      #
      # An absent/empty value is NOT corrupt — that is the legitimate "no
      # allowlist" state written by allowed_domains= when the list is empty.
      # A well-formed empty array ("[]") is likewise not corrupt. A
      # whitespace-only value IS corrupt: no app write path produces one
      # (allowed_domains= writes nil or valid JSON), and allowed_domains
      # above — whose blank guard does not strip — would degrade it to
      # allow-all, the exact silent failure this predicate exists to catch.
      # JSON.parse tolerates surrounding whitespace, so a padded-but-valid
      # value still reads as well-formed.
      #
      # @return [Boolean] true when a value is present but unreadable as an Array
      def allowed_domains_corrupt?
        raw = allowed_domains_json.to_s
        return false if raw.empty?

        !JSON.parse(raw).is_a?(Array)
      rescue JSON::ParserError
        true
      end

      # Validate an email address against the allowed domains list.
      #
      # NOTE: returns true when the list is empty — an unconfigured allowlist
      # means "allow every domain the IdP will authenticate", which is the
      # intended state for providers that control access themselves (Entra ID,
      # see PROVIDER_METADATA). Authentication callers must therefore pair this
      # with allowed_domains_corrupt? so an unreadable list is not mistaken for
      # an unconfigured one.
      #
      # @param email [String] Email address to validate
      # @return [Boolean] true if email domain is allowed
      def valid_email_domain?(email)
        domains = allowed_domains
        return true if domains.empty?

        email_domain = email.to_s.split('@').last&.downcase
        return false if email_domain.nil? || email_domain.empty?

        domains.include?(email_domain)
      end

      # Generate OmniAuth strategy options for runtime injection.
      #
      # @return [Hash] OmniAuth provider options
      # @raise [Onetime::Problem] if provider_type is unsupported
      def to_omniauth_options
        case provider_type
        when 'oidc'
          build_oidc_options
        when 'entra_id'
          build_entra_id_options
        else
          raise Onetime::Problem, "Unsupported SSO provider type: #{provider_type}"
        end
      end

      # Load the associated CustomDomain record.
      #
      # @return [CustomDomain, nil] The domain or nil if not found
      def custom_domain
        Onetime::CustomDomain.find_by_identifier(domain_id)
      rescue Onetime::RecordNotFound
        nil
      end

      # Load the owning Organization via the CustomDomain.
      #
      # @return [Organization, nil] The organization or nil if not found
      def organization
        domain = custom_domain
        return nil unless domain

        Onetime::Organization.load(domain.org_id)
      end

      # Validate that all required fields are present for the provider type.
      #
      # @return [Array<String>] List of validation error messages
      def validation_errors
        errors = []

        errors << 'domain_id is required' if domain_id.to_s.empty?
        errors << 'provider_type is required' if provider_type.to_s.empty?
        errors << "provider_type must be one of: #{PROVIDER_TYPES.join(', ')}" unless PROVIDER_TYPES.include?(provider_type)

        # Check encrypted values for presence
        client_id_val     = begin
                          client_id&.reveal { it }
        rescue StandardError
                          nil
        end
        client_secret_val = begin
                              client_secret&.reveal { it }
        rescue StandardError
                              nil
        end

        errors << 'client_id is required' if client_id_val.to_s.empty?
        errors << 'client_secret is required' if client_secret_val.to_s.empty? && provider_type != 'oidc'

        # Provider-specific field requirements:
        #
        #   | provider_type | tenant_id | issuer | client_secret |
        #   |---------------|-----------|--------|---------------|
        #   | entra_id      | required  | -      | required      |
        #   | oidc          | -         | required | optional    |
        #
        # OIDC supports public clients (PKCE flow) without a client secret.
        # Every tenant provider requires an issuer-bearing field (issuer or
        # tenant_id) — issuerless providers are not configurable (#3902).
        #
        case provider_type
        when 'oidc'
          errors << 'issuer is required for OIDC provider' if issuer.to_s.empty?
        when 'entra_id'
          errors << 'tenant_id is required for Entra ID provider' if tenant_id.to_s.empty?
        end

        errors
      end

      # Check if the configuration is valid.
      #
      # @return [Boolean] true if no validation errors
      def valid?
        validation_errors.empty?
      end

      class << self
        # Returns provider metadata for all supported providers.
        #
        # @return [Hash] Provider type => metadata hash
        def provider_metadata
          PROVIDER_METADATA
        end

        # Returns metadata for a specific provider type.
        #
        # @param provider_type [String] One of PROVIDER_TYPES
        # @return [Hash] Provider metadata or empty hash
        def metadata_for(provider_type)
          PROVIDER_METADATA.fetch(provider_type.to_s, {})
        end

        # Find SSO config by domain ID.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [CustomDomain::SsoConfig, nil] The config or nil if not found
        def find_by_domain_id(domain_id)
          return nil if domain_id.to_s.empty?

          load(domain_id)
        rescue Onetime::RecordNotFound
          nil
        end

        # Why tenant SSO is NOT an available sign-in path for a custom domain,
        # or nil when it IS available.
        #
        # This method owns the availability ladder; tenant_sso_available_for? is
        # the boolean face of it, so there is exactly one implementation of the
        # decision. Callers that only branch use the predicate; callers that
        # must also report WHY (the omniauth runtime hook logs the rejection
        # cause on :omniauth_tenant_sso_not_enabled) use this one.
        #
        # Available only when the domain has its OWN enabled SsoConfig
        # (credentials store) AND SigninConfig.sso_permitted_for? allows SSO —
        # the identical two conditions ConfigSerializer#resolve_tenant_sso_config
        # uses to hand back the tenant provider. Domain-id-only (no request
        # context), so it is the single source of truth shared by the
        # branded-masthead link gate
        # (Core::Views::DomainSerializer#effective_signin_enabled?) and the
        # /signin page gate (via resolve_tenant_sso_config), keeping the masthead
        # Sign In link and the /signin page in agreement for an SSO-only tenant
        # (enabled SsoConfig, no SigninConfig) — the case the link previously hid
        # while the page it points to worked.
        #
        # Scope: TENANT SsoConfig only, not the operator's platform-SSO fallback
        # (allow_platform_fallback_for_tenants?). A branded front door advertises
        # what the DOMAIN OWNER opted into, not a global operator fallback, so a
        # platform-fallback-only domain keeps its /signin page (resolve_signin
        # honors fallback) without lighting up a masthead link. See
        # ConfigSerializer#build_sso_config.
        #
        # Master-switch gate (#3901 follow-up): AUTH_ENABLED=false resolves
        # :auth_disabled before the credential checks. With the master switch
        # off, sessionauth is never registered and every session reads as
        # unauthenticated, so an SSO sign-in could only mint a session the
        # app ignores — display surfaces must not advertise it and the
        # omniauth runtime hook must not inject tenant credentials for it.
        # AUTH_SIGNIN is deliberately NOT consulted: it retires only the
        # password/email path (see SigninConfig.global_signin_enabled).
        #
        # Reasons (rung order matches the checks below):
        #   :auth_disabled             - AUTH_ENABLED master switch is off
        #   :no_sso_config             - no SsoConfig record for the domain
        #   :sso_config_disabled       - record present, its enabled switch is off
        #   :unsupported_provider_type - record's provider_type is not in
        #                                PROVIDER_TYPES (pre-#3902 legacy data;
        #                                see BackfillTenantIssuer)
        #   :sso_not_permitted         - SigninConfig withholds SSO for the domain
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @param auth [Hash, nil] site.authentication settings (injectable for tests)
        # @param sso_config [Onetime::CustomDomain::SsoConfig, nil] the caller's
        #   already-loaded record for domain_id, skipping the redundant lookup
        #   (the omniauth request hook loads it anyway for credential
        #   injection). A record whose domain_id does not match is ignored and
        #   the lookup runs — the availability verdict must never be computed
        #   from another domain's record.
        # @return [Symbol, nil] the failing rung, or nil when tenant SSO is available
        def tenant_sso_unavailable_reason(domain_id, auth: nil, sso_config: nil)
          return :auth_disabled unless Onetime::CustomDomain::SigninConfig.global_auth_enabled(auth)

          config = sso_config&.domain_id == domain_id ? sso_config : find_by_domain_id(domain_id)
          return :no_sso_config if config.nil?
          return :sso_config_disabled unless config.enabled?
          # Defense-in-depth against pre-#3902 stored records: google/github
          # configs predate the OIDC/Entra-only surface and would otherwise
          # reach to_omniauth_options, which raises Onetime::Problem — this
          # rung fails the SAME record closed here instead, so the masthead
          # link and /signin page (both reading this ladder) never advertise
          # a route that would 500.
          return :unsupported_provider_type unless PROVIDER_TYPES.include?(config.provider_type)
          return :sso_not_permitted unless Onetime::CustomDomain::SigninConfig.sso_permitted_for?(domain_id)

          nil
        end

        # Whether tenant SSO is an available sign-in path for a custom domain.
        #
        # Boolean face of tenant_sso_unavailable_reason — see that method for
        # the full semantics (gate ladder, scope, master switch, and the
        # sso_config: pass-through contract). Identical parameters.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @param auth [Hash, nil] site.authentication settings (injectable for tests)
        # @param sso_config [Onetime::CustomDomain::SsoConfig, nil] caller's
        #   already-loaded record for domain_id (mismatched records ignored)
        # @return [Boolean] true if tenant SSO can be used to sign in
        def tenant_sso_available_for?(domain_id, auth: nil, sso_config: nil)
          tenant_sso_unavailable_reason(domain_id, auth: auth, sso_config: sso_config).nil?
        end

        # Whether ANY SSO sign-in path is offered on a CUSTOM DOMAIN host —
        # the domain's own credentials, or the operator's platform providers
        # when tenants are allowed to fall back to them.
        #
        # Wider than tenant_sso_available_for? by exactly the platform-fallback
        # arm, and that is the point: it answers the question
        # ConfigSerializer#build_sso_config answers for the rendered page
        # ("will this host show SSO buttons?"), so the `restrict_to` SSO pin —
        # display (ConfigSerializer#effective_global_restrict_to) and runtime
        # (Auth::RestrictTo.global_restrict_to) — can be computed from ONE
        # predicate on both sides.
        #
        # Why the pin converges HERE rather than on the narrower tenant ladder
        # (ADR-034#restrict-to-is-an-access-control-not-a-display-preference,
        # #4139): with allow_platform_fallback_for_tenants? on and
        # no tenant SsoConfig, the page renders platform SSO buttons and
        # nothing else — password/email default OFF on custom domains — while
        # the narrower predicate left the gate unpinned and therefore MORE
        # permissive than the page, accepting crafted password POSTs on a host
        # that offers only SSO. Converging on the display's answer is the
        # narrowing direction and locks out nobody: the methods it restricts
        # away are ones that host never offered.
        #
        # The masthead link gate deliberately keeps the NARROW predicate (a
        # branded front door advertises what the domain owner opted into, not
        # an operator fallback) — that asymmetry is unchanged.
        #
        # @param domain_id [String, nil] CustomDomain identifier (objid)
        # @param auth [Hash, nil] site.authentication settings (injectable for tests)
        # @return [Boolean] true if the host offers some SSO sign-in path
        def sso_available_for_tenant_host?(domain_id, auth: nil)
          return true if domain_id && tenant_sso_available_for?(domain_id, auth: auth)
          return false unless Onetime.auth_config.allow_platform_fallback_for_tenants?
          return false unless Onetime::CustomDomain::SigninConfig.global_auth_enabled(auth)

          Onetime.auth_config.sso_enabled?
        end

        # Check if a domain has SSO configured.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if SSO config exists
        def exists_for_domain?(domain_id)
          return false if domain_id.to_s.empty?

          exists?(domain_id)
        end

        # Create a new SSO config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @param attrs [Hash] Configuration attributes
        # @return [CustomDomain::SsoConfig] The created config
        # @raise [Onetime::Problem] if config already exists or validation fails
        def create!(domain_id:, **attrs)
          raise Onetime::Problem, 'domain_id is required' if domain_id.to_s.empty?
          raise Onetime::Problem, 'SSO config already exists for this domain' if exists_for_domain?(domain_id)

          config = new(domain_id: domain_id)

          # Set simple fields
          config.provider_type    = attrs[:provider_type] if attrs.key?(:provider_type)
          config.display_name     = attrs[:display_name] if attrs.key?(:display_name)
          config.tenant_id        = attrs[:tenant_id] if attrs.key?(:tenant_id)
          config.issuer           = attrs[:issuer] if attrs.key?(:issuer)
          config.enabled          = attrs[:enabled].to_s if attrs.key?(:enabled)
          config.enforce_sso_only = attrs[:enforce_sso_only].to_s if attrs.key?(:enforce_sso_only)
          config.grant_org_scope  = attrs[:grant_org_scope].to_s if attrs.key?(:grant_org_scope)

          # Set encrypted fields
          config.client_id     = attrs[:client_id] if attrs.key?(:client_id)
          config.client_secret = attrs[:client_secret] if attrs.key?(:client_secret)

          # Set allowed domains
          config.allowed_domains = attrs[:allowed_domains] if attrs.key?(:allowed_domains)

          # Initialize timestamps
          now            = Familia.now.to_i
          config.created = now
          config.updated = now

          unless config.valid?
            raise Onetime::Problem, config.validation_errors.join('; ')
          end

          # Save using Horreum's built-in method
          config.save

          config
        end

        # Delete SSO config for a domain.
        #
        # @param domain_id [String] CustomDomain identifier
        # @return [Boolean] true if deleted, false if not found
        def delete_for_domain!(domain_id)
          return false if domain_id.to_s.empty?

          config = find_by_domain_id(domain_id)
          return false unless config

          # Use Horreum's destroy! which handles main key + instances zset
          config.destroy!

          true
        end

        # List all domain SSO configs.
        #
        # @return [Array<CustomDomain::SsoConfig>] All configs (newest first)
        def all
          instances.revrangeraw(0, -1).filter_map do |identifier|
            load(identifier)
          rescue Onetime::RecordNotFound
            nil
          end
        end

        # Count of domains with SSO configured.
        #
        # @return [Integer] Number of SSO configs
        def count
          instances.size
        end
      end

      private

      def strategy_name
        domain = custom_domain
        raise Onetime::RecordNotFound, "CustomDomain #{domain_id} not found" unless domain

        domain.extid
      end

      def build_oidc_options
        {
          strategy: :openid_connect,
          name: strategy_name,
          scope: [:openid, :email, :profile],
          response_type: :code,
          issuer: issuer,
          discovery: true,
          pkce: true,
          client_options: {
            identifier: client_id&.reveal { it },
            secret: client_secret&.reveal { it },
          },
        }
      end

      def build_entra_id_options
        {
          strategy: :entra_id,
          name: strategy_name,
          client_id: client_id&.reveal { it },
          client_secret: client_secret&.reveal { it },
          tenant_id: tenant_id,
          scope: 'openid profile email',
        }
      end
    end
  end
end
