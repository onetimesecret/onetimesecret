# apps/api/domains/logic/domains/update_domain_brand.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require 'onetime/domain_validation/features'
require_relative '../base'
require_relative '../../policies/domain_config_authorization'

module DomainsAPI::Logic
  module Domains
    # Update Domain Brand Settings
    #
    # @api Updates brand settings for a custom domain including name,
    #   tagline, primary color, font family, corner style, homepage URL,
    #   and default TTL. Returns the updated brand settings.
    #
    # Authorization model (via DomainConfigAuthorization):
    #   1. Load CustomDomain by extid
    #   2. Load Organization via domain.org_id
    #   3. Verify user has manage_org in the organization
    #   4. Verify organization has custom_branding entitlement
    #
    # Read-only counterpart GetDomainBrand skips manage_org so regular
    # members can view the brand page (disabled overlay in the UI).
    #
    class UpdateDomainBrand < DomainsAPI::Logic::Base
      include DomainsAPI::Policies::DomainConfigAuthorization

      SCHEMAS = { response: 'brandSettings' }.freeze

      # Free-text fields that may render in HTML contexts (page titles,
      # email templates, alt attributes, meta tags, TOTP URIs). These are
      # sanitized at the write boundary to strip HTML tags before storage.
      TEXT_FIELDS = %w[
        product_name
        footer_text
        instructions_pre_reveal
        instructions_reveal
        instructions_post_reveal
        description
      ].freeze

      # Expanded color vocabulary (#3646): secondary/background/text colors.
      # Same hex format + normalization as primary_color. WCAG pairing (incl.
      # text-on-background) is enforced by BrandSettings.validate!.
      EXTRA_COLOR_FIELDS = %w[secondary_color background_color text_color].freeze

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

        authorize_domain_config!(@extid)

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

      private

      def validate_brand_settings
        return if @brand_settings.is_a?(Hash)

        OT.ld "[UpdateDomainBrand] Error: Invalid brand settings format - got #{@brand_settings.class}"
        raise_form_error 'Please provide valid brand settings'
      end

      def validate_brand_values
        sanitize_text_fields
        validate_color
        validate_extra_colors
        validate_font
        validate_heading_font
        validate_corner_style
        validate_border_radius
        validate_default_ttl
        validate_urls

        # Model-level validation as defense-in-depth. The per-field checks
        # above produce specific form errors with logging; this catches
        # anything that might slip through on future field additions.
        Onetime::CustomDomain::BrandSettings.validate!(@brand_settings)
      rescue Onetime::Problem => ex
        raise_form_error ex.message
      end

      def validate_color
        color = @brand_settings['primary_color']
        return if color.nil?

        unless Onetime::CustomDomain::BrandSettings.valid_color?(color)
          OT.ld "[UpdateDomainBrand] Error: Invalid color format '#{color}'"
          raise_form_error 'Invalid primary color format - must be hex code (e.g. #FF0000)'
        end

        # Normalize 3-digit hex to 6-digit (e.g. #F00 -> #FF0000)
        @brand_settings['primary_color'] = Onetime::CustomDomain::BrandSettings.normalize_color(color)
      end

      def validate_extra_colors
        EXTRA_COLOR_FIELDS.each do |field|
          color = @brand_settings[field]
          next if color.nil?

          unless Onetime::CustomDomain::BrandSettings.valid_color?(color)
            OT.ld "[UpdateDomainBrand] Error: Invalid #{field} format '#{color}'"
            raise_form_error "Invalid #{field.tr('_', ' ')} format - must be hex code (e.g. #FF0000)"
          end

          @brand_settings[field] = Onetime::CustomDomain::BrandSettings.normalize_color(color)
        end
      end

      def validate_font
        font = @brand_settings['font_family']
        return if font.nil?

        return if Onetime::CustomDomain::BrandSettings.valid_font?(font)

        OT.ld "[UpdateDomainBrand] Error: Invalid font family '#{font}'"
        raise_form_error "Invalid font family - must be one of: #{Onetime::CustomDomain::BrandSettings::FONTS.join(', ')}"
      end

      def validate_heading_font
        font = @brand_settings['heading_font']
        return if font.nil?

        return if Onetime::CustomDomain::BrandSettings.valid_font?(font)

        OT.ld "[UpdateDomainBrand] Error: Invalid heading font '#{font}'"
        raise_form_error "Invalid heading font - must be one of: #{Onetime::CustomDomain::BrandSettings::FONTS.join(', ')}"
      end

      def validate_corner_style
        style = @brand_settings['corner_style']
        return if style.nil?

        return if Onetime::CustomDomain::BrandSettings.valid_corner_style?(style)

        OT.ld "[UpdateDomainBrand] Error: Invalid corner style '#{style}'"
        raise_form_error "Invalid corner style - must be one of: #{Onetime::CustomDomain::BrandSettings::CORNERS.join(', ')}"
      end

      def validate_border_radius
        radius = @brand_settings['border_radius']
        return if radius.nil?

        unless Onetime::CustomDomain::BrandSettings.valid_border_radius?(radius)
          OT.ld "[UpdateDomainBrand] Error: Invalid border radius '#{radius}'"
          raise_form_error(
            "Invalid border radius - must be a preset " \
            "(#{Onetime::CustomDomain::BrandSettings::RADII.join(', ')}) " \
            "or a whole number of pixels 0-#{Onetime::CustomDomain::BrandSettings::RADIUS_MAX}"
          )
        end

        # Normalize named presets to lowercase; leave numeric strings as-is so
        # the frontend can map either form to the --radius-brand CSS variable.
        @brand_settings['border_radius'] = radius.to_s.strip.downcase
      end

      # Currently disabled (see raise_concerns). When re-enabled, uses
      # org-membership-level check rather than the previous user-level check,
      # since domain branding is an org-scoped feature.
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

        # Gate extended TTL values behind entitlement.
        # Intentionally uses org-membership-level check (require_entitlement_in!)
        # rather than the previous user-level check (require_entitlement!), since
        # domain branding is an org-scoped feature — the entitlement should flow
        # from org membership, not personal grants.
        free_ttl = Onetime::Models::Features::WithEntitlements::DEFAULT_FREE_TTL
        if ttl_value > free_ttl
          require_entitlement_in!(@organization, 'extended_default_expiration')
        end

        @brand_settings['default_ttl'] = ttl_value
      end

      def validate_urls
        %w[logo_url logo_dark_url favicon_url].each do |url_field|
          url = @brand_settings[url_field]
          next if url.nil?

          unless Onetime::CustomDomain::BrandSettings.valid_url?(url)
            OT.ld "[UpdateDomainBrand] Error: Invalid URL format for '#{url_field}': #{url}"
            raise_form_error "Invalid #{url_field.tr('_', ' ')} - must be https:// URL or relative path starting with /"
          end
        end
      end

      def sanitize_text_fields
        TEXT_FIELDS.each do |field|
          next unless @brand_settings.key?(field) && @brand_settings[field].is_a?(String)

          @brand_settings[field] = sanitize_plain_text(@brand_settings[field], max_length: 500)
        end
      end

      def valid_extid?(extid)
        extid.match?(/\A[a-z0-9]+\z/)
      end
    end
  end
end
