require 'base64'

module Onetime::Logic
  module Domains
    class GetDomainLogo < OT::Logic::Base
      attr_reader :logo_data, :logo_content_type

      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :get_domain_logo

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error "Domain not found" unless @custom_domain

        raise_form_error "Logo not found" unless @custom_domain.brand['image_encoded']
      end

      def process
        OT.ld "[GetDomainLogo] Processing logo for #{@custom_domain.display_domain}"

        @logo_data = Base64.strict_decode64(@custom_domain.brand['image_encoded'])
        @logo_content_type = @custom_domain.brand['image_content_type'] || 'image/png'  # Default to PNG if not specified
      end

      def success_data
        {
          logo_data: @logo_data,
          content_type: @logo_content_type
        }
      end
    end
  end
end
