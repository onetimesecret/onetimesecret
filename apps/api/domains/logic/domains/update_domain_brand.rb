# apps/api/domains/logic/domains/update_domain_brand.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require 'onetime/domain_validation/features'
require_relative '../base'
require_relative '../concerns/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    # Update Domain Brand Settings
    #
    # @api Updates brand settings for a custom domain including name,
    #   tagline, primary color, font family, corner style, homepage URL,
    #   and default TTL. Requires the custom_branding entitlement and
    #   manage_org permission. Returns the updated brand settings.
    class UpdateDomainBrand < DomainsAPI::Logic::Base
      include DomainsAPI::Logic::Concerns::DomainConfigAuthorization

      SCHEMAS = { response: 'brandSettings' }.freeze

      attr_reader :greenlighted, :brand_settings, :display_domain, :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])

        # Use BrandSettings.members as the single source of truth for valid keys.
        # Feature toggles (allow_public_homepage, allow_public_api) are no longer
        # in BrandSettings — they're managed via dedicated HomepageConfig/ApiConfig
        # endpoints, so being absent from members is the gate.
        valid_keys = Onetime::CustomDomain::BrandSettings.members.map(&:to_s)

        # Filter to valid keys and normalize to strings (HTTP params have string keys)
        @brand_settings = params['brand']&.transform_keys(&:to_s)&.slice(*valid_keys) || {}
      end

      def raise_concerns
        OT.ld "[UpdateDomainBrand] Validating domain: #{@extid} with settings: #{@brand_settings.keys}"

        raise_form_error 'Please provide a domain ID' if @extid.to_s.empty?
        raise_form_error 'Invalid domain identifier format' unless valid_extid?(@extid)

        authorize_domain_brand!(@extid)

        validate_brand_settings
        validate_brand_values

        # Disabled while we figure out whether we want this entitlement at all
        # validate_privacy_defaults_entitlement
      end

      def process
        @greenlighted = true

        return error('Custom domain not found') unless @custom_domain

        update_brand_settings
      end

      def success_data
        # Clear memoized brand_settings to get fresh data after update
        @custom_domain.instance_variable_set(:@brand_settings, nil)
        {
          user_id: @cust.objid,
          record: @custom_domain.safe_dump.fetch(:brand, {}),
        }
      end

      # Update the brand settings for the custom domain
      # Familia v2 hashkeys auto-serialize via serialize_value, so pass raw values
      def update_brand_settings
        brand_settings.each do |key, value|
          if value.nil?
            OT.ld "[UpdateDomainBrand] Removing brand setting: #{key}"
            custom_domain.brand.remove(key)
          else
            OT.ld "[UpdateDomainBrand] Updating brand setting: #{key} => #{value} (#{value.class})"
            custom_domain.brand[key] = value
          end
        end

        custom_domain.updated = OT.now.to_i
        custom_domain.save

        success_data
      end

      # Validate URL format
      def valid_url?(url)
        uri = URI.parse(url)
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      rescue URI::InvalidURIError
        false
      end

      protected

      def config_entitlement
        'custom_branding'
      end

      def config_entitlement_error
        'Custom branding requires the custom_branding entitlement. Please upgrade your plan.'
      end

      def authorize_domain_brand!(domain_id)
        authorize_domain_config!(domain_id)
      end

      private

      def validate_brand_settings
        return if @brand_settings.is_a?(Hash)

        OT.ld "[UpdateDomainBrand] Error: Invalid brand settings format - got #{@brand_settings.class}"
        raise_form_error 'Please provide valid brand settings'
      end

      def validate_brand_values
        validate_color
        validate_font
        validate_corner_style
        validate_default_ttl
      end

      def validate_color
        color = @brand_settings['primary_color']
        return if color.nil?

        return if Onetime::CustomDomain::BrandSettings.valid_color?(color)

        OT.ld "[UpdateDomainBrand] Error: Invalid color format '#{color}'"
        raise_form_error 'Invalid primary color format - must be hex code (e.g. #FF0000)'
      end

      def validate_font
        font = @brand_settings['font_family']
        return if font.nil?

        return if Onetime::CustomDomain::BrandSettings.valid_font?(font)

        OT.ld "[UpdateDomainBrand] Error: Invalid font family '#{font}'"
        raise_form_error "Invalid font family - must be one of: #{Onetime::CustomDomain::BrandSettings::FONTS.join(', ')}"
      end

      def validate_corner_style
        style = @brand_settings['corner_style']
        return if style.nil?

        return if Onetime::CustomDomain::BrandSettings.valid_corner_style?(style)

        OT.ld "[UpdateDomainBrand] Error: Invalid corner style '#{style}'"
        raise_form_error "Invalid corner style - must be one of: #{Onetime::CustomDomain::BrandSettings::CORNERS.join(', ')}"
      end

      def validate_privacy_defaults_entitlement
        privacy_keys = %w[default_ttl passphrase_required notify_enabled]
        return unless privacy_keys.any? { |k| @brand_settings.key?(k) }

        require_entitlement_in!(@organization, 'custom_privacy_defaults')
      end

      def validate_default_ttl
        ttl = @brand_settings['default_ttl']
        return if ttl.nil?

        ttl_value = ttl
        if ttl.is_a?(String)
          begin
            ttl_value = Integer(ttl, 10)
          rescue ArgumentError
            OT.ld "[UpdateDomainBrand] Error: Invalid integer string for default_ttl '#{ttl}'"
            raise_form_error 'Invalid default TTL - must be a positive integer (seconds)'
          end
        end

        unless ttl_value.is_a?(Integer) && ttl_value.positive?
          OT.ld "[UpdateDomainBrand] Error: Invalid default_ttl '#{ttl}'"
          raise_form_error 'Invalid default TTL - must be a positive integer (seconds)'
        end

        # Gate extended TTL values behind entitlement
        free_ttl = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
        if ttl_value > free_ttl
          require_entitlement_in!(@organization, 'extended_default_expiration')
        end

        @brand_settings['default_ttl'] = ttl_value
      end

      def valid_extid?(extid)
        extid.match?(/\A[a-z0-9]+\z/)
      end
    end
  end
end
