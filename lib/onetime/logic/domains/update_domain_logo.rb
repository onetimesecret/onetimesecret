require 'base64'

require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class UpdateDomainLogo < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @domain_id = params[:domain].to_s.strip
        @logo = params[:logo]

        if @logo.is_a?(Hash) && @logo[:tempfile]
          @logo_file = @logo[:tempfile]
          @logo_filename = @logo[:filename]
          @logo_content_type = @logo[:type]
        end
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        OT.ld "[UpdateDomainBrand] Raising concerns for domain_id: #{@domain_id}"
        limit_action :update_domain_brand

        raise_form_error "Domain ID is required" if @domain_id.nil? || @domain_id.empty?

        # Check if the domain exists and belongs to the current customer
        @custom_domain = OT::CustomDomain.load(@domain_id, @cust.custid)
        raise_form_error "Invalid domain ID" unless @custom_domain

        # Validate the logo file
        if @logo_file
          raise_form_error "Logo file is too large" if @logo_file.size > 1 * 1024 * 1024  # 1 MB
          # Raise an error if the file type is not one of the allowed image types
          # Allowed types: JPEG, PNG, GIF, SVG, WEBP, BMP, TIFF
          raise_form_error "Invalid file type" unless ['image/jpeg', 'image/png', 'image/gif', 'image/svg+xml', 'image/webp', 'image/bmp', 'image/tiff'].include?(@logo_content_type)
        else
          raise_form_error "Logo file is required"
        end
      end

      def process
        @greenlighted = true
        if @logo_file
          # Read the file content
          file_content = @logo_file.read

          # Encode the file content to Base64
          encoded_content = Base64.strict_encode64(file_content)

          # Save the encoded image and metadata
          @custom_domain.brand['image_encoded'] = encoded_content
          @custom_domain.brand['image_filename'] = @logo_filename
          @custom_domain.brand['image_content_type'] = @logo_content_type

          # Save the custom domain
          @custom_domain.save
        end
      end

      def success_data
        OT.ld "[UpdateDomainLogo] Preparing success data for domain_id: #{@domain_id}"
        {
          record: @custom_domain.safe_dump,
          details: {
            msg: "Logo updated successfully for #{@custom_domain.display_domain}"
          }
        }
      end

    end
  end
end
