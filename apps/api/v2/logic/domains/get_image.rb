require_relative '../base'

module V2::Logic
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
    class GetImage < V2::Logic::Base
      attr_reader :custom_domain_id, :filename, :custom_domain, :image_type, :image_ext, :content_type,
        :content_length, :image_data, :encoded_content

      def process_params
        # Sanitize the id to allow only alphanumeric characters
        @custom_domain_id = params[:custom_domain_id].to_s.gsub(/[^a-zA-Z0-9]/, '')

        # One of: logo, icon. CustomDomain must have a matching hashkey field.
        tmp_image_type = params[:image_type].to_s.gsub(/[^a-zA-Z0-9]/, '')
        @image_type    = %w[logo icon].include?(tmp_image_type) ? tmp_image_type : nil

        # We capture the file extension for the image but we just log
        # it. The response content type is determined by the stored value.
        tmp_image_ext = params[:image_ext].to_s.gsub(/[^a-zA-Z0-9]/, '')
        @image_ext    = tmp_image_ext

        OT.ld "[GetImage] domain_id=#{custom_domain_id} type=#{image_type} ext=#{image_ext}"
      end

      def raise_concerns
        raise_not_found 'Missing domain ID' if custom_domain_id.empty?

        tmp_custom_domain = Onetime::CustomDomain.find_by_identifier custom_domain_id
        raise_not_found 'Domain not found' unless tmp_custom_domain
        @custom_domain    = tmp_custom_domain # make it available after all concerns

        # Safely retrieve the logo filename from the custom domain's brand
        _image_field&.[]('filename')
        content_type = _image_field.[]('content_type')

        raise_not_found 'No content type' unless content_type
        @content_type = content_type

        encoded_content  = _image_field['encoded']
        raise_not_found 'No content' unless encoded_content
        @encoded_content = encoded_content
      end

      def process
        # Decode the base64 content back to binary
        @image_data     = Base64.strict_decode64(encoded_content)
        @content_length = @image_data&.bytesize.to_s || '0'

        success_data
      end

      def success_data
        @image_data
      end

      # e.g. custom_domain.logo
      def _image_field
        custom_domain.send(image_type) # logo, icon
      end
      private :_image_field
    end
  end
end
