require 'base64'

require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    unless defined?(IMAGE_MIME_TYPES)
      IMAGE_MIME_TYPES = %w[
        image/jpeg image/png image/gif image/svg+xml image/webp image/bmp image/tiff
      ]
    end

    class UpdateDomainImage < OT::Logic::Base
      attr_reader :greenlighted, :image, :display_domain, :custom_domain

      @field = nil

      class << self
        attr_reader :field
      end

      # Processes the parameters for the domain logo update.
      # Extracts and sets instance variables for the display domain and uploaded image file.
      # Handles cases where the image parameter is either a hash (from a form upload) or a file object directly.
      def process_params
        # Strip any leading/trailing whitespace from the domain parameter and set it to an instance variable.
        @display_domain = params[:domain].to_s.strip

        # Retrieve the image parameter from the request.
        @image = params[:image]

        # Check if the image parameter is a hash (typical for form uploads).
        if @image.is_a?(Hash) && @image[:tempfile]
          # Extract the tempfile, filename, and content type from the hash.
          @uploaded_file = @image[:tempfile]
          @filename = @image[:filename]
          @content_type = @image[:type]

        # Check if the image parameter is a file object directly
        # (e.g. it's the Tempfile or StringIO).
        elsif @image.respond_to?(:read)
          # Set the uploaded file to the image parameter directly.
          @uploaded_file = @image
          # Extract the original filename if available.
          @filename = @image.original_filename if @image.respond_to?(:original_filename)
          # Extract the content type if available.
          @content_type = @image.content_type if @image.respond_to?(:content_type)
        end

      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        limit_action :update_domain_brand

        raise_form_error "Domain is required" if @display_domain.empty?

        # Check if the domain exists and belongs to the current customer
        @custom_domain = OT::CustomDomain.load(@display_domain, @cust.custid)
        raise_form_error "Invalid Domain" unless @custom_domain

        # Validate the logo file
        raise_form_error "Logo file is required" unless @uploaded_file

        if @uploaded_file.size > 1 * 1024 * 1024  # 1 MB
          raise_form_error "Logo file is too large"
        end
        # Raise an error if the file type is not one of the allowed image types
        # Allowed types: JPEG, PNG, GIF, SVG, WEBP, BMP, TIFF
        unless IMAGE_MIME_TYPES.include?(@content_type)
          raise_form_error "Invalid file type"
        end

        @greenlighted = true
      end

      def process
        # Read the file content
        file_content = @uploaded_file.read

        # Encode the file content to Base64
        encoded_content = Base64.strict_encode64(file_content)

        # Add the encoded image and metadata to the custom domain
        # image field (e.g. logo, icon, etc). These fields are their
        # own redis hash keys and not in the main custom domain
        # object hash. That means these attribtues are being
        # directly saved into redis and we do not need to call
        # custom_domain.save to persist these changes.
        _image_field['encoded'] = encoded_content
        _image_field['filename'] = @filename
        _image_field['content_type'] = @content_type
      end

      def success_data
        klass = self.class
        OT.ld "[#{klass}] Preparing #{klass.field} response for: #{@display_domain}"
        {
          record: @custom_domain.safe_dump,
          details: {
            msg: "Logo updated successfully for #{@custom_domain.display_domain}"
          }
        }
      end

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(self.class.field)
      end
      private :_image_field

    end

    class UpdateDomainLogo < UpdateDomainImage
      @field = :logo
    end

    class UpdateDomainIcon < UpdateDomainImage
      @field = :icon
    end

  end
end
