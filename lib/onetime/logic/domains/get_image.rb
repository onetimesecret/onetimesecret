
require_relative '../base'

module Onetime::Logic
  module Domains

    # /imagine/b79b17281be7264f778c/logo.png
    class GetImage < OT::Logic::Base
      attr_reader :custom_domain_id, :filename, :custom_domain
      attr_reader :content_type, :content_length, :image_data

      def process_params
        # Sanitize the filename to allow only alphanumeric characters
        @custom_domain_id = params[:custom_domain_id].to_s.gsub(/[^a-zA-Z0-9]/, '')

        # Sanitize the filename to allow only alphanumeric
        # characters, periods, dashes, and underscores
        @filename = params[:filename].to_s.gsub(/[^a-zA-Z0-9._-]/, '')
      end

      def raise_concerns
        limit_action :get_image

        raise_not_found "Missing domain ID" if @custom_domain_id.empty?

        custom_domain = OT::CustomDomain.from_identifier custom_domain_id
        raise_not_found "Domain not found" unless custom_domain

        # Safely retrieve the logo filename from the custom domain's brand
        logo_filename = custom_domain.image1&.[]('filename')
        content_type = custom_domain.image1.[]('iontent_type')

        raise_not_found "No content type" unless content_type

        # If the filename does not match the stored filename, return a 404
        if !logo_filename || filename != logo_filename
          raise_not_found "File not found"
        end

        @logo_filename = logo_filename
        @content_type = content_type
        @custom_domain = custom_domain # make it available after all concerns
      end

      def process
        encoded_content = custom_domain.image1.[]('image_encoded')

        # Decode the base64 content back to binary
        @image_data = Base64.strict_decode64(encoded_content)
        @content_length = @image_data&.bytesize.to_s || '0'
      end
    end

  end
end
