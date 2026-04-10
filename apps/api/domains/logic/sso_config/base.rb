# apps/api/domains/logic/sso_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/sso_config'
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

          OT.info '[SsoConfig] Authorization denied: missing manage_sso entitlement',
            { org_id: organization.extid, actor: cust&.custid }.to_json
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
          unless OT.conf.dig('features', 'organizations', 'sso_enabled')
            OT.info '[SsoConfig] Authorization denied: SSO feature flag disabled',
              { domain_id: domain_id, actor: cust&.custid }.to_json
            raise_form_error('Organization SSO is not enabled on this instance', error_type: :forbidden)
          end

          @custom_domain = load_custom_domain(domain_id)
          @organization  = load_organization_for_domain(@custom_domain)

          verify_organization_owner(@organization)
          verify_manage_sso_entitlement(@organization)

          OT.ld format('[SsoConfig] Authorization granted: domain=%s org=%s actor=%s', @custom_domain.display_domain, @organization.extid, cust&.custid)
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
      end
    end
  end
end
