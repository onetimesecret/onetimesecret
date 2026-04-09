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
      # base classes (ApiConfig, HomepageConfig, etc.):
      #
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner (colonel bypass)
      #   4. Verify organization has the required entitlement
      #
      # Including classes must define:
      #   - `config_entitlement` returning the entitlement name string
      #   - `config_entitlement_error` returning the error message string
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

          raise_form_error(
            config_entitlement_error,
            error_type: :forbidden,
          )
        end

        # Full authorization check for domain config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # Sets @custom_domain and @organization as side effects.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_config!(domain_id)
          @custom_domain = load_custom_domain(domain_id)
          @organization  = load_organization_for_domain(@custom_domain)

          verify_organization_owner(@organization)
          verify_config_entitlement(@organization)
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
      end
    end
  end
end
