# apps/api/domains/logic/domains/get_domain_brand.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    # Get Domain Brand Settings
    #
    # @api Retrieves the brand settings for a custom domain. Returns the
    #   brand configuration including name, tagline, colors, fonts, and
    #   homepage settings.
    #
    # Authorization model (read-only — no DomainConfigAuthorization):
    #   1. Verify user belongs to an organization (require_organization!)
    #   2. Load CustomDomain by extid
    #   3. Verify user owns the domain (owner? check)
    #   4. Verify user's membership has custom_branding entitlement
    #
    # Unlike the write counterpart (UpdateDomainBrand), this endpoint
    # does NOT require manage_org. Regular org members can read brand
    # settings so the UI can render the brand page as a disabled overlay,
    # keeping premium features visible per modern SaaS convention.
    #
    class GetDomainBrand < DomainsAPI::Logic::Base
      SCHEMAS = { response: 'brandSettings' }.freeze

      attr_reader :brand_settings, :display_domain, :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)

        raise_form_error 'Domain not found' unless @custom_domain

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end

        domain_org = @custom_domain.primary_organization
        raise_form_error 'Domain has no associated organization' unless domain_org
        require_entitlement_in!(domain_org, 'custom_branding')
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
    end
  end
end
