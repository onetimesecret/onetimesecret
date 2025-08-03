require 'base64'
require 'fastimage'

require 'onetime/cluster'
require_relative '../base'

module V2::Logic
  module Domains
    unless defined?(IMAGE_MIME_TYPES)
      IMAGE_MIME_TYPES = %w[
        image/jpeg image/png image/gif image/svg+xml image/webp image/bmp image/tiff
      ]
      MAX_IMAGE_BYTES  = 1 * 1024 * 1024 # 1 MB
    end

    class UpdateDomainImage < V2::Logic::Base
      attr_reader :greenlighted, :image, :display_domain, :custom_domain, :content_type, :filename, :height, :width,
        :ratio, :bytes

      @field = nil

      class << self
        attr_reader :field
      end

      # Processes the parameters for the domain logo update.
      # Extracts and sets instance variables for the display domain and uploaded image file.
      # Handles cases where the image parameter is either a hash (from a form upload) or a file object directly.
      def process_params
        # Strip any leading/trailing whitespace from the domain parameter and set it to an instance variable.
        @domain_input = params[:domain].to_s.strip

        # Retrieve the image parameter from the request.
        @image = params[:image]

        # Check if the image parameter is a hash (typical for form uploads).
        if @image.is_a?(Hash) && @image[:tempfile]
          # Extract the tempfile, filename, and content type from the hash.
          @uploaded_file = @image[:tempfile]
          @filename      = @image[:filename]
          @content_type  = @image[:type]

        # Check if the image parameter is a file object directly
        # (e.g. it's the Tempfile or StringIO).
        elsif @image.respond_to?(:read)
          # Set the uploaded file to the image parameter directly.
          @uploaded_file = @image
          # Extract the original filename if available.
          @filename      = @image.original_filename if @image.respond_to?(:original_filename)
          # Extract the content type if available.
          @content_type  = @image.content_type if @image.respond_to?(:content_type)
        end
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        raise_form_error 'Domain is required' if @domain_input.empty?

        # Check if the domain exists and belongs to the current customer
        @custom_domain = V2::CustomDomain.load(@domain_input, @cust.custid)
        raise_form_error 'Invalid Domain' unless @custom_domain

        @display_domain = @domain_input

        # Validate the logo file
        raise_form_error 'Image file is required' unless @uploaded_file

        @bytes = @uploaded_file.size
        raise_form_error 'Image file is too large' if bytes > MAX_IMAGE_BYTES

        # Raise an error if the file type is not one of the allowed image types
        # Allowed types: JPEG, PNG, GIF, SVG, WEBP, BMP, TIFF
        raise_form_error 'Invalid file type' unless IMAGE_MIME_TYPES.include?(@content_type)

        @greenlighted = true
      end

      def process
        # Read the file content and encode to Base64
        file_content    = @uploaded_file.read
        encoded_content = Base64.strict_encode64(file_content)

        # Create data URI for FastImage
        data_uri = "data:#{content_type};base64,#{encoded_content}"

        dimensions    = FastImage.size(data_uri)
        width, height = dimensions
        ratio         = width.to_f / height

        # Add the encoded image and metadata to the custom domain
        # image field (e.g. logo, icon, etc). These fields are their
        # own redis hash keys and not in the main custom domain
        # object hash. That means these attribtues are being
        # directly saved into redis and we do not need to call
        # custom_domain.save to persist these changes.
        _image_field['encoded']      = encoded_content
        _image_field['filename']     = @filename
        _image_field['content_type'] = @content_type
        _image_field['height']       = height
        _image_field['width']        = width
        _image_field['ratio']        = ratio
        _image_field['bytes']        = @bytes
      end

      def success_data
        klass = self.class
        OT.ld "[#{klass}] Preparing #{klass.field} response for: #{@display_domain}"
        {
          record: _image_field.hgetall,
          details: {
            msg: "Image updated successfully for #{@custom_domain.display_domain}",
          },
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
