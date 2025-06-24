require 'onetime/cluster'
require_relative '../base'

module V2::Logic
  module Domains
    class UpdateDomainBrand < V2::Logic::Base
      attr_reader :greenlighted, :brand_settings, :display_domain, :custom_domain

      def process_params
        @domain_id = params[:domain].to_s.strip
        valid_keys = [
          :logo, # e.g. "image1"
          :primary_color,
          :instructions_pre_reveal,
          :instructions_reveal,
          :instructions_post_reveal,
          :button_text_light,
          :font_family,
          :corner_style,
          :allow_public_homepage,
          :allow_public_api,
          :locale,
        ]

        # Filter out invalid keys and convert keys to symbols
        @brand_settings = params[:brand]&.transform_keys(&:to_sym)&.slice(*valid_keys) || {}
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        OT.ld "[UpdateDomainBrand] Validating domain: #{@domain_id} with settings: #{@brand_settings.keys}"

        validate_domain
        validate_brand_settings
        limit_action :update_domain_brand
        validate_brand_values
      end

      def process
        @greenlighted = true

        return error('Custom domain not found') unless @custom_domain

        update_brand_settings
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump.fetch(:brand, {}),
          details: {},
        }
      end

      # Update the brand settings for the custom domain
      # These keys are expected to match those listed in
      # the brand setting schema.
      def update_brand_settings
        current_brand = custom_domain.brand || {}

        # Step 1: Remove keys that are nil in the request
        brand_settings.each do |key, value|
          if value.nil?
            OT.ld "[UpdateDomainBrand] Removing brand setting: #{key}"
            current_brand.delete(key.to_s)
          end
        end

        # Step 2: Update remaining values
        brand_settings.each do |key, value| # rubocop:disable Style/CombinableLoops
          next if value.nil?

          OT.ld "[UpdateDomainBrand] Updating brand setting: #{key} => #{value} (#{value.class})"
          custom_domain.brand[key.to_s] = value.to_s # everything in redis is a string
        end

        custom_domain.updated = Time.now.to_i
        custom_domain.save
      end

      # Validate URL format
      def valid_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end

      private

      def validate_domain
        if @domain_id.nil? || @domain_id.empty?
          OT.ld '[UpdateDomainBrand] Error: Missing domain ID'
          raise_form_error 'Please provide a domain ID'
        end

        @custom_domain = V2::CustomDomain.load(@domain_id, @cust.custid)
        unless custom_domain&.exists?
          OT.ld "[UpdateDomainBrand] Error: Domain #{@domain_id} not found for customer #{@cust.custid}"
          raise_form_error 'Domain not found'
        end
      end

      def validate_brand_settings
        unless @brand_settings.is_a?(Hash)
          OT.ld "[UpdateDomainBrand] Error: Invalid brand settings format - got #{@brand_settings.class}"
          raise_form_error 'Please provide valid brand settings'
        end
      end

      def validate_brand_values
        validate_color
        validate_font
        validate_corner_style
      end

      def validate_color
        color = @brand_settings[:primary_color]
        return if color.nil?

        unless valid_color?(color)
          OT.ld "[UpdateDomainBrand] Error: Invalid color format '#{color}'"
          raise_form_error 'Invalid primary color format - must be hex code (e.g. #FF0000)'
        end
      end

      def validate_font
        font = @brand_settings[:font_family]
        return if font.nil?

        unless valid_font_family?(font)
          OT.ld "[UpdateDomainBrand] Error: Invalid font family '#{font}'"
          raise_form_error 'Invalid font family - must be one of: sans, serif, mono'
        end
      end

      def validate_corner_style
        style = @brand_settings[:corner_style]
        return if style.nil?

        unless valid_corner_style?(style)
          OT.ld "[UpdateDomainBrand] Error: Invalid corner style '#{style}'"
          raise_form_error 'Invalid corner style - must be one of: rounded, square, pill'
        end
      end

      # Validate color format (hex code)
      def valid_color?(color)
        color.match?(/^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/)
      end

      # Validate font family
      def valid_font_family?(font)
        %w[sans serif mono].include?(font.to_s.downcase)
      end

      # Validate button style
      def valid_corner_style?(style)
        %w[rounded square pill].include?(style.to_s.downcase)
      end
    end
  end
end
