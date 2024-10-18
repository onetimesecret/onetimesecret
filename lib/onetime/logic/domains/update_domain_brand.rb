require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class UpdateDomainBrand < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @domain_id = params[:domain_id]
        @brand_settings = params[:brand_settings]
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        greenlight
        error("Missing domain_id") if @domain_id.nil? || @domain_id.empty?
        error("Missing brand_settings") if @brand_settings.nil? || !@brand_settings.is_a?(Hash)
        error("Invalid logo URL") if @brand_settings[:logo] && !valid_url?(@brand_settings[:logo])
        error("Invalid primary color") if @brand_settings[:primaryColor] && !valid_color?(@brand_settings[:primaryColor])
        error("Invalid font family") if @brand_settings[:fontFamily] && !valid_font_family?(@brand_settings[:fontFamily])
        error("Invalid button style") if @brand_settings[:buttonStyle] && !valid_button_style?(@brand_settings[:buttonStyle])
      end

      def process
        return unless greenlighted?

        @custom_domain = OT::CustomDomain.find_by_domain(@domain_id)
        return error("Custom domain not found") unless @custom_domain

        update_brand_settings
        success("Brand settings updated successfully")
      end

      private


      # Update the brand settings for the custom domain
      def update_brand_settings
        valid_keys = [:logo, :primaryColor, :description, :fontFamily, :buttonStyle]
        @brand_settings.each do |key, value|
          if valid_keys.include?(key.to_sym)
            @custom_domain.brand[key.to_s] = value
          end
        end
        @custom_domain.updated = Time.now.to_i
        @custom_domain.save
      end

      # Validate URL format
      def valid_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end

      # Validate color format (hex code)
      def valid_color?(color)
        color.match?(/^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/)
      end

      # Validate font family
      def valid_font_family?(font)
        %w[sans-serif serif monospace].include?(font)
      end

      # Validate button style
      def valid_button_style?(style)
        %w[rounded square pill].include?(style)
      end
    end
  end
end
