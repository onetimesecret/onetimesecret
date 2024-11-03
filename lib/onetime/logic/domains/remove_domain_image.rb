require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class RemoveDomainImage < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      def process_params
        @domain_input = params['domain'].to_s.strip
      end

      def raise_concerns
        OT.ld "[#{self.class}] Raising concerns for domain_input: #{@domain_input}"
        limit_action :remove_domain_logo

        raise_form_error "Domain ID is required" if @domain_input.empty?

        @custom_domain = OT::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error "Invalid domain ID" unless @custom_domain

        @display_domain = @domain_input

        raise_form_error "No image exists for this domain" unless image_exists?

        @greenlighted = true
      end

      def process
        remove_image
        @custom_domain.save
      end

      def success_data
        OT.ld "[#{self.class}] Preparing success data for display_domain: #{@display_domain}"
        {
          record: nil,
          details: {
            msg: "Image removed successfully for #{@custom_domain.display_domain}"
          }
        }
      end

      def image_exists?
        _image_field.key?('encoded')
      end
      private :image_exists?

      def remove_image
        # We don't delete the redis key itself, at least not explicitly. In Redis
        # if all fields are deleted from a hash, the hash key itself is deleted.
        _image_field.delete('encoded')
        _image_field.delete('filename')
        _image_field.delete('content_type')
      end
      private :remove_image

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
