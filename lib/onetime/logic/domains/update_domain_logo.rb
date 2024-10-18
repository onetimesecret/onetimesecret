require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class UpdateDomainLogo < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @domain_id = params[:domain].to_s.strip
        @logo = params[:logo]
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        OT.ld "[UpdateDomainBrand] Raising concerns for domain_id: #{@domain_id}"

        raise_form_error "Domain ID is required" if @domain_id.nil? || @domain_id.empty?

        # Check if the domain exists and belongs to the current customer
        @custom_domain = OT::CustomDomain.find_by_id_and_custid(@domain_id, @cust.custid)
        raise_form_error "Invalid domain ID" unless @custom_domain

        # Validate the logo file
        if @logo
          raise_form_error "Logo file is too large" if @logo.size > 5.megabytes
          raise_form_error "Invalid file format" unless ['image/jpeg', 'image/png', 'image/gif'].include?(@logo.content_type)
        else
          raise_form_error "Logo file is required"
        end

        limit_action :update_domain_brand
      end

      def process
        @greenlighted = true
        # Implementation for processing the logo update will go here
      end

      def success_data
        OT.ld "[UpdateDomainLogo] Preparing success data for domain_id: #{@domain_id}"
        {
          domain: {
            id: @custom_domain.id,
            custid: @custom_domain.custid,
            domain: @custom_domain.domain,
            logo_url: @logo_url,
            updated_at: @custom_domain.updated_at.utc.iso8601
          },
          msg: "Logo updated successfully for #{@custom_domain.domain}"
        }
      end

    end
  end
end
