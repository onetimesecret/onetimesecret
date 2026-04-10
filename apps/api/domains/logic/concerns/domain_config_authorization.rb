# apps/api/domains/logic/concerns/domain_config_authorization.rb
#
# frozen_string_literal: true

require 'onetime/application/authorization_policies'

module DomainsAPI
  module Logic
    module Concerns
      # Shared authorization logic for domain config endpoints.
      #
      # Provides the common authorization flow used by domain config
      # base classes (ApiConfig, HomepageConfig, SenderConfig, SsoConfig):
      #
      #   1. Check feature flag (if config_feature_flag is defined)
      #   2. Load CustomDomain by domain_id (extid)
      #   3. Load Organization via domain.org_id
      #   4. Verify user is organization owner (colonel bypass)
      #   5. Verify organization has the required entitlement
      #
      # Including classes must define:
      #   - `config_entitlement` returning the entitlement name string
      #   - `config_entitlement_error` returning the error message string
      #
      # Including classes may optionally define:
      #   - `config_feature_flag` returning the feature flag path
      #      (e.g. 'custom_mail_enabled') checked under
      #      features.organizations in config. Returns nil by default
      #      (no feature flag check).
      #   - `config_feature_flag_error` returning the error message when
      #      the feature flag is disabled.
      #   - `config_log_tag` returning a string tag for structured log
      #      messages (e.g. 'SenderConfig'). Defaults to the enclosing
      #      module's short name.
      #
      # Example:
      #
      #   class Base < DomainsAPI::Logic::Base
      #     include DomainsAPI::Logic::Concerns::DomainConfigAuthorization
      #
      #     protected
      #
      #     def config_entitlement
      #       'api_access'
      #     end
      #
      #     def config_entitlement_error
      #       'API configuration requires the api_access entitlement. Please upgrade your plan.'
      #     end
      #   end
      #
      module DomainConfigAuthorization
        def self.included(base)
          base.include Onetime::Application::AuthorizationPolicies
        end

        protected

        # Load and verify domain exists.
        #
        # @param domain_id [String] Domain extid
        # @return [Onetime::CustomDomain] The loaded domain
        # @raise [FormError] if domain not found
        def load_custom_domain(domain_id)
          domain = Onetime::CustomDomain.find_by_extid(domain_id)
          raise_not_found("Domain not found: #{domain_id}") if domain.nil?
          domain
        end

        # Load organization from domain's org_id.
        #
        # @param domain [Onetime::CustomDomain] The domain
        # @return [Onetime::Organization] The owning organization
        # @raise [FormError] if organization not found
        def load_organization_for_domain(domain)
          org = Onetime::Organization.load(domain.org_id)
          raise_not_found("Organization not found for domain: #{domain.display_domain}") if org.nil?
          org
        end

        # Verify current user owns the organization.
        #
        # Colonels (site admins) have automatic superuser bypass.
        # Otherwise, user must be organization owner.
        #
        # @param organization [Onetime::Organization]
        # @raise [FormError] If user is not owner and not admin
        def verify_organization_owner(organization)
          verify_one_of_roles!(
            colonel: true,
            custom_check: -> { organization.owner?(cust) },
            error_message: 'Only organization owner can perform this action',
          )
        end

        # Verify organization has the required entitlement.
        #
        # Delegates to `config_entitlement` for the entitlement name and
        # `config_entitlement_error` for the error message. Both must be
        # defined by the including class.
        #
        # @param organization [Onetime::Organization]
        # @raise [FormError] if entitlement not present
        def verify_config_entitlement(organization)
          return if organization.can?(config_entitlement)

          OT.info format('[%s] Authorization denied: missing %s entitlement', config_log_tag, config_entitlement),
            { org_id: organization.extid, actor: cust&.custid }.to_json
          raise_form_error(
            config_entitlement_error,
            error_type: :forbidden,
          )
        end

        # Feature flag path under features.organizations config.
        # Override in subclass to require a feature flag. Returns nil
        # by default (no feature flag check).
        #
        # @return [String, nil] Feature flag key or nil
        def config_feature_flag
          nil
        end

        # Error message when the feature flag is disabled.
        # Override in subclass to customize.
        #
        # @return [String]
        def config_feature_flag_error
          "#{config_log_tag} is not enabled on this instance"
        end

        # Log tag for structured log messages. Defaults to the
        # enclosing module's short name (e.g. 'SsoConfig').
        #
        # @return [String]
        def config_log_tag
          self.class.name&.split('::')&.[](-2) || self.class.to_s
        end

        # Full authorization check for domain config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # Sets @custom_domain and @organization as side effects.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_config!(domain_id)
          verify_feature_flag!(domain_id)

          @custom_domain = load_custom_domain(domain_id)
          @organization  = load_organization_for_domain(@custom_domain)

          verify_organization_owner(@organization)
          verify_config_entitlement(@organization)

          OT.ld format('[%s] Authorization granted: domain=%s org=%s actor=%s', config_log_tag, @custom_domain.display_domain, @organization.extid, cust&.custid)
        end

        # Parse boolean from various input formats.
        #
        # @param value [Boolean, String, Integer, nil] Value to parse
        # @return [Boolean] true if value represents truthy, false otherwise
        def parse_boolean(value)
          case value
          when true, 'true', '1', 1
            true
          else
            false
          end
        end

        private

        # Check the feature flag if one is configured.
        #
        # @param domain_id [String] Domain extid (for logging)
        # @raise [FormError] if feature flag is disabled
        def verify_feature_flag!(domain_id)
          flag = config_feature_flag
          return if flag.nil?
          return if OT.conf.dig('features', 'organizations', flag)

          OT.info format('[%s] Authorization denied: %s feature flag disabled', config_log_tag, flag),
            { domain_id: domain_id, actor: cust&.custid }.to_json
          raise_form_error(config_feature_flag_error, error_type: :forbidden)
        end
      end
    end
  end
end
