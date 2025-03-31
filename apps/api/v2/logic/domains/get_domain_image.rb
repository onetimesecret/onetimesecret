require 'base64'

module V2::Logic
  module Domains
    class GetDomainImage < V2::Logic::Base
      attr_reader :display_domain, :image_field, :image, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @domain_input = params[:domain].to_s.strip
      end

      def raise_concerns
        raise_form_error "Please enter a domain" if @domain_input.empty?

        unless V2::CustomDomain.valid?(@domain_input)
          raise_form_error "Not a valid public domain"
        end

        # Add rate limiting after basic value validation, before data access
        limit_action :get_domain_logo

        @custom_domain = V2::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error "Domain not found" unless custom_domain

        @display_domain = @domain_input # Only after it's known to be a good value

        @image = self._image_field
        raise_not_found "Image not found" unless image && image['encoded']
      end

      def process
        OT.ld "[#{self.class}] Logo for #{custom_domain.display_domain}"

        image[:content_type] ||= 'application/octet-stream' # ¯\_(ツ)_/¯
      end

      def success_data
        {
          record: image.hgetall,  # encoded filename content_type
          details: {
          },
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
