# apps/api/domains/logic/sso_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/sso_config'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI
  module Logic
    module SsoConfig
      # Base class for Domain SSO Configuration endpoints.
      #
      # Authorization model:
      #   1. Check sso_enabled feature flag
      #   2. Load CustomDomain by domain_id (extid)
      #   3. Load Organization via domain.org_id
      #   4. Verify user is organization owner
      #   5. Verify organization has manage_sso entitlement
      #
      class Base < DomainsAPI::Logic::Base
        include DomainsAPI::Policies::DomainConfigAuthorization

        attr_reader :custom_domain, :organization

        protected

        # Entitlement required for SSO config operations.
        def config_entitlement
          'manage_sso'
        end

        # Error message when manage_sso entitlement is missing.
        def config_entitlement_error
          'SSO management requires the manage_sso entitlement. Please upgrade your plan.'
        end

        # Feature flag under features.organizations config.
        def config_feature_flag
          'sso_enabled'
        end

        # Error message when feature flag is disabled.
        def config_feature_flag_error
          'Organization SSO is not enabled on this instance'
        end

        # Full authorization check for domain SSO config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_sso!(domain_id)
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

        # Sanitize and validate URL input.
        #
        # @param value [String, nil] URL string to sanitize
        # @return [String] Sanitized URL or empty string if invalid
        def sanitize_url(value)
          return '' if value.nil?

          url = value.to_s.strip
          # Basic URL validation - must start with https:// for security
          return '' unless url.start_with?('https://')

          url
        end

        # Validate that enforce_sso_only is not enabled when SSO is disabled.
        #
        # @param enabled [Boolean] Whether SSO is enabled (effective value for PATCH, direct for PUT)
        # @param enforce_sso_only [Boolean] Whether SSO-only mode is enforced
        # @raise [Onetime::FormError] if enforce_sso_only is true but enabled is false
        def validate_enforce_sso_requires_enabled(enabled, enforce_sso_only)
          return unless enforce_sso_only && !enabled

          raise_form_error('Enable SSO before enforcing SSO-only mode', field: :enforce_sso_only, error_type: :invalid)
        end
      end
    end
  end
end
