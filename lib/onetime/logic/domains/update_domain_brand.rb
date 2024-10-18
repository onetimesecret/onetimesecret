require_relative '../base'
require_relative '../../cluster'

module Onetime::Logic
  module Domains
    class UpdateDomainBrand < OT::Logic::Base
      attr_reader :greenlighted, :display_domain, :custom_domain

      def process_params
        @domain_id = params[:domain].to_s.strip
        @brand_settings = params[:brand_settings]
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        OT.ld "[UpdateDomainBrand] Raising any concerns about domain_id: #{@domain_id}, brand_settings: #{@brand_settings}"

        raise_form_error "Please provide a domain ID" if @domain_id.nil? || @domain_id.empty?
        raise_form_error "Please provide brand settings" if @brand_settings.nil? || !@brand_settings.is_a?(Hash)

        limit_action :update_domain_brand

        if @brand_settings[:logo]
          raise_form_error "Invalid logo URL" unless valid_url?(@brand_settings[:logo])
        end

        if @brand_settings[:primaryColor]
          raise_form_error "Invalid primary color" unless valid_color?(@brand_settings[:primaryColor])
        end

        if @brand_settings[:fontFamily]
          raise_form_error "Invalid font family" unless valid_font_family?(@brand_settings[:fontFamily])
        end

        if @brand_settings[:buttonStyle]
          raise_form_error "Invalid button style" unless valid_button_style?(@brand_settings[:buttonStyle])
        end

        # You might want to add a check here to ensure the domain exists
        # raise_form_error "Domain not found" unless OT::CustomDomain.exists?(@domain_id)
      end

      def process
        @greenlighted = true

        @custom_domain = OT::CustomDomain.find_by_domain(@domain_id)
        return error("Custom domain not found") unless @custom_domain

        update_brand_settings
      end

      def success_data
        {
          custid: @cust.custid,
          record: @custom_domain.safe_dump,
          details: {
            cluster: OT::Cluster::Features.cluster_safe_dump
          }
        }
      end

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
