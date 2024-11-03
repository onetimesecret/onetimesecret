require 'base64'

module Onetime::Logic
  module Domains
    class GetDomainImage < OT::Logic::Base
      attr_reader :image, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?
        raise_form_error "Not a valid public domain" unless OT::CustomDomain.valid?(@domain_input)

        limit_action :get_domain_logo

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error "Domain not found" unless @custom_domain

        @image = @custom_domain._image_field
        raise_form_error "Logo not found" unless image['encoded']
      end

      def process
        OT.ld "[GetDomainLogo] Processing logo for #{@custom_domain.display_domain}"

        @logo_data = Base64.strict_decode64(image['encoded'])
        @logo_content_type = image['content_type'] || 'image/png'  # Default to PNG if not specified
      end

      def success_data
        {
          record: image,  # encoded filename content_type
          details: {

          }
        }
      end

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(self.class.field)
      end
      private :_image_field

    end

    class GetDomainLogo < GetDomainImage
      @field = :logo
    end

    class GetDomainIcon < GetDomainImage
      @field = :icon
    end

  end
end
