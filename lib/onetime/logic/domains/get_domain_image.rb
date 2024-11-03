require 'base64'

module Onetime::Logic
  module Domains
    class GetDomainImage < OT::Logic::Base
      attr_reader :display_domain, :image_field, :image, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @image_field = params[:image_field].to_s
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        # The URL path should end in /logo or /icon, for example. That value
        # must match a hashkey field defined in CustomDomain.
        unless OT::CustomDomain.fields.include?(image_field.to_sym)
          raise_form_error "Invalid image field #{image_field}"
        end

        raise_form_error "Please enter a domain" if @domain_input.empty?

        unless OT::CustomDomain.valid?(@domain_input)
          raise_form_error "Not a valid public domain"
        end

        # Add rate limiting after basic value validation, before data access
        limit_action :get_domain_logo

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error "Domain not found" unless @custom_domain

        @display_domain = @domain_input # Only after it's known to be a good value

        @image = @custom_domain._image_field
        raise_form_error "Logo not found" unless image['encoded']
      end

      def process
        OT.ld "[GetDomainLogo] Processing logo for #{@custom_domain.display_domain}"

        image[:content_type] ||= 'application/octet-stream' # ¯\_(ツ)_/¯
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
