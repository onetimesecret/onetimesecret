# apps/api/domains/logic/domains/get_domain_brand.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    # Get Domain Brand Settings
    #
    # @api Retrieves the brand settings for a custom domain. Returns the
    #   brand configuration including name, tagline, colors, fonts, and
    #   homepage settings.
    #
    # Authorization model (read-only, via DomainConfigAuthorization helpers):
    #   1. Load CustomDomain by extid
    #   2. Load Organization via domain.org_id
    #   3. Verify user's membership has custom_branding entitlement
    #
    # Unlike the write counterpart (UpdateDomainBrand), this endpoint
    # does NOT require manage_org. Regular org members can read brand
    # settings so the UI can render the brand page as a disabled overlay,
    # keeping premium features visible per modern SaaS convention.
    #
    class GetDomainBrand < DomainsAPI::Logic::Base
      include DomainsAPI::Policies::DomainConfigAuthorization

      SCHEMAS = { response: 'brandSettings' }.freeze

      attr_reader :brand_settings, :display_domain, :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?
        raise_form_error 'Invalid domain identifier format' unless @extid.match?(/\A[a-z0-9]+\z/)

        @custom_domain = load_custom_domain(@extid)
        @organization  = load_organization_for_domain(@custom_domain)
        require_entitlement_in!(@organization, config_entitlement)

        # Domain-scope enforcement (#3384)
        membership = Onetime::OrganizationMembership.find_by_org_customer(@organization.objid, @cust.objid)
        if membership && !membership.can_access_domain?(@custom_domain)
          raise_not_found 'Domain not found'
        end
      end

      def process
        OT.ld "[GetDomainBrand] Processing #{@custom_domain.display_domain}"
        @display_domain = @custom_domain.display_domain

        success_data
      end

      def success_data
        {
          user_id: @cust.objid,
          record: @custom_domain.safe_dump.fetch(:brand, {}),
        }
      end

      protected

      def config_entitlement
        'custom_branding'
      end

      def config_entitlement_error
        'Custom branding requires the custom_branding entitlement. Please upgrade your plan.'
      end
    end
  end
end
