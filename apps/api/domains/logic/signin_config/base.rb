# apps/api/domains/logic/signin_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
require 'onetime/models/custom_domain/sso_config'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI
  module Logic
    module SigninConfig
      # Base class for Domain Signin Configuration endpoints.
      #
      # Authorization model:
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner (manage_org)
      #   4. Verify organization has custom_signin_config entitlement
      #
      class Base < DomainsAPI::Logic::Base
        include DomainsAPI::Policies::DomainConfigAuthorization

        attr_reader :custom_domain, :organization

        protected

        # Entitlement required for signin config operations.
        def config_entitlement
          'custom_signin_config'
        end

        # Error message when entitlement is missing.
        def config_entitlement_error
          'Sign-in configuration requires the custom_signin_config entitlement. Please upgrade your plan.'
        end

        # Full authorization check for domain signin config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_signin_config!(domain_id)
          authorize_domain_config!(domain_id)
        end

        # Resolution details accompanying every signin-config response (ADR-024).
        #
        # The settings UI displays the resolver's output instead of re-deriving
        # availability from the raw flag pair — client-side derivation is the
        # drift ADR-024 exists to kill. global_restrict_to lets the UI show the
        # inherited method restriction while the domain is unconfigured.
        #
        # effective_enabled uses the CUSTOM-DOMAIN resolver (default OFF,
        # opt-in) with the tenant-SSO carve-out — NOT resolve_signin_enabled.
        # These settings describe a custom domain, so an unconfigured domain
        # must read "disabled" even when the canonical site's sign-in is on
        # (#3814), while an SSO-only tenant (enabled SsoConfig, no
        # SigninConfig) reads "enabled" to match its working masthead link and
        # /signin page (same shared authority as
        # Core::Views::DomainSerializer#effective_signin_enabled?).
        #
        # effective_restrict_to is the resolver's output verbatim
        # (ADR-034#settings-api-serializes-effective-restrict-to), so the
        # settings UI stops re-deriving the effective restriction
        # from global_restrict_to client-side. global_restrict_to stays: it
        # names the *inherited* restriction, which the UI still labels
        # separately from what resolves for this domain.
        #
        # tenant_sso carries the SsoConfig availability ladder's verdict
        # (#4111) — the same operator question ("what will this host actually
        # offer, and why"), answered by the same authority the runtime uses,
        # never re-derived from raw flags in Vue.
        #
        # @param config [Onetime::CustomDomain::SigninConfig, nil] nil when unconfigured
        # @param domain_id [String] CustomDomain identifier (objid) for the SSO carve-out
        # @return [Hash] global_enabled, effective_enabled, global_restrict_to,
        #   effective_restrict_to, tenant_sso
        def signin_override_details(config, domain_id)
          global          = Onetime::CustomDomain::SigninConfig.global_signin_enabled
          global_restrict = Onetime.auth_config.restrict_to

          # The value this HOST inherits, which is not always the operator's own
          # restriction: an SSO-only custom domain (no enabled SigninConfig,
          # tenant or platform SSO available) inherits the 'sso' HOST PIN. Asked
          # through the shared SigninConfig.inherited_restrict_to — the same call
          # the /signin page and the route gate make. This page used to hand the
          # resolver Onetime.auth_config.restrict_to verbatim and so reported
          # `unrestricted` for a host whose Rodauth routes the gate was already
          # restricting to SSO: a fail-OPEN divergence of exactly the kind
          # ADR-034#degradation-is-fail-closed forbids, caught by
          # apps/web/core/spec/views/serializers/restrict_to_parity_spec.rb.
          #
          # custom_host is always true here: these settings describe a custom
          # domain. The details.global_restrict_to field below keeps the
          # OPERATOR's own value — the UI labels the inherited operator
          # restriction separately from what resolves for this host.
          inherited_restrict = Onetime::CustomDomain::SigninConfig.inherited_restrict_to(
            config,
            domain_id: domain_id,
            custom_host: true,
          )

          {
            global_enabled: global,
            effective_enabled: Onetime::CustomDomain::SigninConfig.resolve_signin_enabled_for_custom_domain(
              global,
              config,
              domain_id: domain_id,
            ),
            global_restrict_to: global_restrict,
            # #to_wire is the resolution's own serialization (single
            # implementation, shared with GET /api/invite/:token) — this app
            # no longer carries a private copy of the wire shape.
            effective_restrict_to: Onetime::CustomDomain::SigninConfig.resolve_restrict_to(
              inherited_restrict,
              config,
              # Post-boot availability of the global restriction
              # (ADR-034#degradation-is-fail-closed),
              # asked through the SHARED gatherer — the same call the route
              # gate and the /signin page make, so this page reports what those
              # two enforce rather than a third answer. custom_host is always
              # true here: these settings describe a custom domain, so an
              # INHERITED global restriction must be narrowed by that domain's
              # capabilities exactly as it is at request time. Without it the
              # page showed `restricted/password` for a domain whose Rodauth
              # routes the gate had already taken to 404 (#4139).
              available: Onetime::CustomDomain::SigninConfig.restriction_available_for_request?(
                inherited_restrict,
                config,
                domain_id: domain_id,
                custom_host: true,
              ),
            ).to_wire,
            tenant_sso: tenant_sso_details(domain_id),
          }
        end

        # Tenant-SSO availability verdict for the settings UI (#4111).
        #
        # Reads the ladder that decides tenant SSO at runtime
        # (SsoConfig.tenant_sso_unavailable_reason) rather than the connection
        # record's own stored flag, so the settings page can report the actual
        # blocking rung — :no_sso_config, :sso_config_disabled,
        # :sso_not_permitted, :auth_disabled, :unsupported_provider_type.
        # The #4107 regression went unnoticed for two months because no
        # surface reported it.
        #
        # @param domain_id [String] CustomDomain identifier (objid)
        # @return [Hash] available (Boolean), unavailable_reason (String or nil)
        def tenant_sso_details(domain_id)
          reason = Onetime::CustomDomain::SsoConfig.tenant_sso_unavailable_reason(domain_id)
          {
            available: reason.nil?,
            unavailable_reason: reason&.to_s,
          }
        end

        # Validate restrict_to value against known values.
        #
        # @param value [String, nil] The restrict_to value
        # @raise [Onetime::FormError] if value is invalid
        def validate_restrict_to(value)
          return if value.nil?
          return if Onetime::CustomDomain::SigninConfig::RESTRICT_TO_VALUES.include?(value)

          valid_values = Onetime::CustomDomain::SigninConfig::RESTRICT_TO_VALUES.join(', ')
          raise_form_error(
            "restrict_to must be one of: #{valid_values}",
            field: :restrict_to,
            error_type: :invalid,
          )
        end
      end
    end
  end
end
