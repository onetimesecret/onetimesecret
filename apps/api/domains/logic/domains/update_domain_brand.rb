# apps/api/domains/logic/domains/update_domain_brand.rb
#
# frozen_string_literal: true

require 'onetime/domain_validation/strategy'
require_relative '../base'

module DomainsAPI::Logic
  module Domains
    class UpdateDomainBrand < DomainsAPI::Logic::Base
      attr_reader :greenlighted, :brand_settings, :display_domain, :custom_domain

      def process_params
        @extid = sanitize_identifier(params['extid'])

        # Use BrandSettings.members as the single source of truth for valid keys
        valid_keys = Onetime::CustomDomain::BrandSettings.members.map(&:to_s)

        # Filter to valid keys and normalize to strings (HTTP params have string keys)
        @brand_settings = params['brand']&.transform_keys(&:to_s)&.slice(*valid_keys) || {}
      end

      # Validate the input parameters
      # Sets error messages if any parameter is invalid
      def raise_concerns
        OT.ld "[UpdateDomainBrand] Validating domain: #{@extid} with settings: #{@brand_settings.keys}"

        validate_domain
        validate_brand_settings

        validate_brand_values
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
          record: @custom_domain.brand_settings.to_h,
          details: {},
        }
      end

      # Update the brand settings for the custom domain
      # Familia v2 hashkeys auto-serialize via serialize_value, so pass raw values
      def update_brand_settings
        # Update or remove brand settings - Familia handles JSON serialization automatically
        brand_settings.each do |key, value|
          if value.nil?
            OT.ld "[UpdateDomainBrand] Removing brand setting: #{key}"
            custom_domain.brand.remove(key)
          else
            OT.ld "[UpdateDomainBrand] Updating brand setting: #{key} => #{value} (#{value.class})"
            custom_domain.brand[key] = value
          end
        end

        custom_domain.updated = Familia.now.to_i
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

      private

      def validate_domain
        if @extid.nil? || @extid.empty?
          OT.ld '[UpdateDomainBrand] Error: Missing domain ID'
          raise_form_error 'Please provide a domain ID'
        end

        # Validate extid format (alphanumeric only, no dots/special chars)
        # This catches cases where domain name is passed instead of extid
        unless valid_extid?(@extid)
          OT.ld "[UpdateDomainBrand] Error: Invalid extid format '#{@extid}'"
          raise_form_error 'Invalid domain identifier format'
        end

        # Get customer's organization for domain ownership
        # Organization available via @organization
        require_organization!

        @custom_domain = Onetime::CustomDomain.find_by_extid(@extid)

        raise_form_error 'Domain not found' unless @custom_domain&.exists?

        # Verify the customer owns this domain through their organization
        unless @custom_domain.owner?(@cust)
          OT.ld "[UpdateDomainBrand] Error: Domain #{@extid} not owned by organization #{organization.objid}"
          raise_form_error 'Domain not found'
        end
      end

      def validate_brand_settings
        return if @brand_settings.is_a?(Hash)

        OT.ld "[UpdateDomainBrand] Error: Invalid brand settings format - got #{@brand_settings.class}"
        raise_form_error 'Please provide valid brand settings'
      end

      def validate_brand_values
        sanitize_text_fields
        validate_color
        validate_font
        validate_corner_style
        validate_default_ttl

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

      def validate_default_ttl
        ttl = @brand_settings['default_ttl']
        return if ttl.nil?

        # Coerce to integer if string with strict validation
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

        # Update the brand_settings hash with the coerced value
        @brand_settings['default_ttl'] = ttl_value
      end

      # Strip HTML tags from free-text brand settings to prevent XSS.
      # Uses sanitize_plain_text from InputSanitizers which strips all
      # HTML via the Sanitize gem and normalizes whitespace.
      def sanitize_text_fields
        TEXT_FIELDS.each do |field|
          next unless @brand_settings.key?(field) && @brand_settings[field].is_a?(String)

          @brand_settings[field] = sanitize_plain_text(@brand_settings[field], max_length: 500)
        end
      end

      # Validate extid format (lowercase alphanumeric only)
      # extids are generated identifiers like "abc123def456"
      # Domain names contain dots and are not valid extids
      def valid_extid?(extid)
        extid.match?(/\A[a-z0-9]+\z/)
      end
    end
  end
end
