# apps/api/domains/logic/domains/get_domain_brand.rb
#
# frozen_string_literal: true

require 'onetime/cluster'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class GetDomainBrand < DomainsAPI::Logic::Base
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
