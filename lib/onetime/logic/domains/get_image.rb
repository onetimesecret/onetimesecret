
require_relative '../base'

module Onetime::Logic
  module Domains

    # Get an image from a custom domain
    #
    # Unlike the v2 API image endpoints, this endpoint uses 2 parameters:
    #   1. custom_domain_id: The ID of the custom domain
    #   2. filename: The name of the image file
    #
    # Both need to be provided in the URL and 404 if either is missing.
    #
    # e.g.
    #   /imagine/b79b17281be7264f778c/logo.png
    #
    class GetImage < OT::Logic::Base
      attr_reader :custom_domain_id, :filename, :custom_domain, :image_type
      attr_reader :content_type, :content_length, :image_data, :encoded_content

      def process_params
        # Sanitize the filename to allow only alphanumeric characters
        @custom_domain_id = params[:custom_domain_id].to_s.gsub(/[^a-zA-Z0-9]/, '')

        # One of: logo, icon. Must match a CustomDomain hashkey field.
        image_type = params[:image_type].to_s.gsub(/[^a-zA-Z0-9]/, '')
        @image_type = %w[logo icon].include?(image_type) ? image_type : nil

        # Sanitize the filename to allow only alphanumeric
        # characters, periods, dashes, and underscores
        @filename = params[:filename].to_s.gsub(/[^a-zA-Z0-9._-]/, '')
      end

      def raise_concerns
        limit_action :get_image

        raise_not_found "Missing domain ID" if @custom_domain_id.empty?

        custom_domain = OT::CustomDomain.from_identifier custom_domain_id
        raise_not_found "Domain not found" unless custom_domain
        @custom_domain = custom_domain # make it available after all concerns

        # Safely retrieve the logo filename from the custom domain's brand
        logo_filename = _image_field&.[]('filename')
        content_type = _image_field.[]('content_type')

        raise_not_found "No content type" unless content_type
        @content_type = content_type

        # If the filename does not match the stored filename, return a 404
        if !logo_filename || filename != logo_filename
          raise_not_found "File not found"
        end

        @logo_filename = logo_filename

        encoded_content = _image_field['encoded']
        raise_not_found "No content" unless encoded_content
        @encoded_content = encoded_content
      end

      def process
        # Decode the base64 content back to binary
        @image_data = Base64.strict_decode64(encoded_content)
        @content_length = @image_data&.bytesize.to_s || '0'
      end

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(image_type) # logo, icon
      end
      private :_image_field
    end

  end
end
