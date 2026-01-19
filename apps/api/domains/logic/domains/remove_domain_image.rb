# apps/api/domains/logic/domains/remove_domain_image.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class RemoveDomainImage < DomainsAPI::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @extid = sanitize_identifier(params['extid'])
      end

      def raise_concerns
        OT.ld "[#{self.class}] Raising concerns for extid: #{@extid}"

        raise_form_error 'Domain ID is required' if @extid.empty?

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)
        raise_form_error 'Invalid Domain' unless @custom_domain

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          raise_form_error 'Invalid Domain'
        end

        @display_domain = @custom_domain.display_domain

        raise_form_error 'No image exists for this domain' unless image_exists?

        @greenlighted = true
      end

      def process
        _image_field.delete! # delete the entire db hash key
        @custom_domain.save

        success_data
      end

      def success_data
        OT.ld "[#{self.class}] Preparing success data for display_domain: #{display_domain}"
        {
          record: nil,
          details: {
            msg: "Image removed successfully for #{@custom_domain.display_domain}",
          },
        }
      end

      def image_exists?
        _image_field.key?('encoded')
      end
      private :image_exists?

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(self.class.field)
      end
      private :_image_field
    end

    class RemoveDomainLogo < RemoveDomainImage
      @field = :logo
    end

    class RemoveDomainIcon < RemoveDomainImage
      @field = :icon
    end
  end
end
