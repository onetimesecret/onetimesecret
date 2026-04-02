# apps/api/domains/logic/incoming_config/base.rb
#
# frozen_string_literal: true

require 'onetime/models/custom_domain/incoming_config'
require 'onetime/application/authorization_policies'

module DomainsAPI
  module Logic
    module IncomingConfig
      # Base class for Domain Incoming Configuration endpoints.
      #
      # Authorization model:
      #   1. Load CustomDomain by domain_id (extid)
      #   2. Load Organization via domain.org_id
      #   3. Verify user is organization owner
      #   4. Verify organization has incoming_secrets entitlement
      #
      # This ensures incoming config management requires both ownership
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

        # Verify organization has incoming_secrets entitlement.
        #
        # @param organization [Onetime::Organization]
        # @raise [FormError] if entitlement not present
        def verify_incoming_secrets_entitlement(organization)
          return if organization.can?('incoming_secrets')

          raise_form_error(
            'Incoming secrets management requires the incoming_secrets entitlement. Please upgrade your plan.',
            error_type: :forbidden,
          )
        end

        # Full authorization check for domain incoming config operations.
        # Loads domain and organization, verifies ownership and entitlement.
        #
        # @param domain_id [String] Domain extid
        # @return [void]
        def authorize_domain_incoming!(domain_id)
          unless OT.conf.dig('features', 'incoming', 'enabled')
            raise_form_error('Incoming secrets is not enabled on this instance', error_type: :forbidden)
          end

          @custom_domain = load_custom_domain(domain_id)
          @organization  = load_organization_for_domain(@custom_domain)

          verify_organization_owner(@organization)
          verify_incoming_secrets_entitlement(@organization)
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

        # Parse recipients from request body.
        #
        # @param value [Array, nil] Recipients array from request
        # @return [Array<Hash>] Normalized recipients with email and name keys
        def parse_recipients(value)
          return [] if value.nil?
          return [] unless value.is_a?(Array)

          value.filter_map do |r|
            next nil unless r.is_a?(Hash)

            email = (r['email'] || r[:email]).to_s.strip.downcase
            name  = (r['name'] || r[:name]).to_s.strip

            next nil if email.empty?

            { email: email, name: name.empty? ? email.split('@').first : name }
          end
        end
      end
    end
  end
end
