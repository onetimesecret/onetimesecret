require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class GetDomainBrand < OT::Logic::Base
      attr_reader :brand_settings, :display_domain, :custom_domain

      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :get_domain_brand

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust.custid)

        raise_form_error "Domain not found" unless @custom_domain
      end

      def process
        OT.ld "[GetDomainBrand] Processing #{@custom_domain.display_domain}"
        @display_domain = @custom_domain.display_domain
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump.fetch(:brand, {}),
        }
      end

    end
  end
end
