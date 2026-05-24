# apps/api/domains/logic/signup_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/signup_config'
require_relative '../concerns/domain_config_authorization'

module DomainsAPI
  module Logic
    module SignupConfig
      # Base class for Domain Signup Configuration endpoints.
      #
      # Authorization model:
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner
      #   4. Verify organization has custom_signup_validation entitlement
      #
      class Base < DomainsAPI::Logic::Base
        include DomainsAPI::Logic::Concerns::DomainConfigAuthorization

        attr_reader :custom_domain, :organization

        protected

        # Entitlement required for signup config operations.
        def config_entitlement
          'custom_signup_validation'
        end

        # Error message when entitlement is missing.
        def config_entitlement_error
          'Signup validation configuration requires the custom_signup_validation entitlement. Please upgrade your plan.'
        end

        # Full authorization check for domain signup config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_signup_config!(domain_id)
          authorize_domain_config!(domain_id)
        end

        # Parse allowed domains from string or array input.
        #
        # @param value [String, Array, nil] Comma-separated string or array of domains
        # @return [Array<String>] Normalized array of lowercase domain strings
        def parse_allowed_domains(value)
          return [] if value.nil?
          return value if value.is_a?(Array)

          # Handle comma-separated string
          if value.is_a?(String)
            value.split(',').map { it.strip.downcase }.reject(&:empty?)
          else
            []
          end
        end

        # Validate that validation_strategy is a known type.
        #
        # @param strategy [String] The validation strategy
        # @raise [Onetime::FormError] if strategy is invalid
        def validate_strategy_type(strategy)
          return if Onetime::CustomDomain::SignupConfig::STRATEGY_TYPES.include?(strategy)

          valid_types = Onetime::CustomDomain::SignupConfig::STRATEGY_TYPES.join(', ')
          raise_form_error(
            "validation_strategy must be one of: #{valid_types}",
            field: :validation_strategy,
            error_type: :invalid,
          )
        end

        # Validate that domain_allowlist strategy has at least one domain.
        #
        # @param strategy [String] The validation strategy
        # @param domains [Array<String>] The allowed domains
        # @raise [Onetime::FormError] if domain_allowlist but no domains
        def validate_allowlist_has_domains(strategy, domains)
          return unless strategy == 'domain_allowlist'
          return if domains && !domains.empty?

          raise_form_error(
            'allowed_signup_domains is required when validation_strategy is domain_allowlist',
            field: :allowed_signup_domains,
            error_type: :missing,
          )
        end
      end
    end
  end
end
