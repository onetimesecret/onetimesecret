# apps/api/domains/logic/sso_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/domain_sso_config'
require 'onetime/application/authorization_policies'

module DomainsAPI
  module Logic
    module SsoConfig
      # Base class for Domain SSO Configuration endpoints.
      #
      # Authorization model:
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner
      #   4. Verify organization has manage_sso entitlement
      #
      # This ensures SSO config management requires both ownership
      # and the appropriate plan entitlement.
      #
      class Base < DomainsAPI::Logic::Base
        include Onetime::Application::AuthorizationPolicies

        attr_reader :custom_domain, :organization

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

        # Verify organization has manage_sso entitlement.
        #
        # @param organization [Onetime::Organization]
        # @raise [FormError] if entitlement not present
        def verify_manage_sso_entitlement(organization)
          return if organization.can?('manage_sso')

          raise_form_error(
            'SSO management requires the manage_sso entitlement. Please upgrade your plan.',
            error_type: :forbidden,
          )
        end

        # Full authorization check for domain SSO config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_sso!(domain_id)
          @custom_domain = load_custom_domain(domain_id)
          @organization  = load_organization_for_domain(@custom_domain)

          verify_organization_owner(@organization)
          verify_manage_sso_entitlement(@organization)
        end
      end
    end
  end
end
