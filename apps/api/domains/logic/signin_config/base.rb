# apps/api/domains/logic/signin_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signin_config'
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
        # @param config [Onetime::CustomDomain::SigninConfig, nil] nil when unconfigured
        # @return [Hash] global_enabled, effective_enabled, global_restrict_to
        def signin_override_details(config)
          global = Onetime::CustomDomain::SigninConfig.global_signin_enabled
          {
            global_enabled: global,
            effective_enabled: Onetime::CustomDomain::SigninConfig.resolve_signin_enabled(global, config),
            global_restrict_to: Onetime.auth_config.restrict_to,
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
