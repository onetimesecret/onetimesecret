# apps/api/account/logic/domains/get_domain_image.rb
#
# frozen_string_literal: true

require 'base64'

module AccountAPI::Logic
  module Domains
    class GetDomainImage < AccountAPI::Logic::Base
      attr_reader :display_domain, :image_field, :image, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @extid = params['extid'].to_s.strip
      end

      def raise_concerns
        raise_form_error 'Please provide a domain ID' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)
        raise_form_error 'Domain not found' unless custom_domain

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          raise_form_error 'Domain not found'
        end

        @display_domain = @custom_domain.display_domain

        @image = _image_field
        raise_not_found 'Image not found' unless image && image['encoded']
      end

      def process
        OT.ld "[#{self.class}] Logo for #{custom_domain.display_domain}"

        image[:content_type] ||= 'application/octet-stream' # ¯\_(ツ)_/¯

        success_data
      end

      def success_data
        {
          record: image.hgetall, # encoded filename content_type
          details: {},
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
