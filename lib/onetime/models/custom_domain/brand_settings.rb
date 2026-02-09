# lib/onetime/models/custom_domain/brand_settings.rb
#
# frozen_string_literal: true

require 'uri'

module Onetime
  class CustomDomain
    # Centralized schema for CustomDomain brand settings using Ruby 3.2+ Data.define.
    # Provides a single source of truth for field names, types, defaults, and validation.
    #
    # @example Creating from a hash
    #   settings = BrandSettings.from_hash(primary_color: '#FF0000', font_family: 'serif')
    #   settings.primary_color  #=> '#FF0000'
    #   settings.font_family    #=> 'serif'
    #
    # @example Converting for Redis storage
    #   settings.to_h_for_storage
    #   #=> {"primary_color"=>"\"#FF0000\"", "font_family"=>"\"serif\"", ...}
    #
    # @example Validation
    #   BrandSettings.valid_color?('#FF0000')  #=> true
    #   BrandSettings.valid_font?('sans')      #=> true
    #
    module BrandSettingsConstants
      # Static fallback defaults used when OT.conf is not available (e.g. during boot).
      # At runtime, use BrandSettingsConstants.defaults which reads from config.
      DEFAULTS = {
        font_family: 'sans',
        corner_style: 'rounded',
        primary_color: '#dc4a22',
        locale: 'en',
        button_text_light: true,
        allow_public_homepage: false,
        allow_public_api: false,
        default_ttl: nil,
        passphrase_required: false,
        notify_enabled: false,
      }.freeze

      # Global brand defaults for site-wide settings that are not per-domain.
      # These are NOT members of the BrandSettings Data class and are not
      # stored in Redis per-domain. Used as fallbacks in email templates,
      # views, and initializers.
      GLOBAL_DEFAULTS = {
        support_email: 'support@onetimesecret.com',
        product_name: 'OTS',
        totp_issuer: 'OTS',
        logo_url: nil,
      }.freeze

      # Returns defaults with primary_color resolved from brand config.
      # Falls back to DEFAULTS when OT.conf is not available.
      def self.defaults
        color = if defined?(OT) && OT.respond_to?(:conf) && OT.conf
                  OT.conf.dig('brand', 'primary_color')
                end
        DEFAULTS.merge(primary_color: color || DEFAULTS[:primary_color])
      end

      # Returns global defaults resolved from brand config at runtime.
      # Falls back to GLOBAL_DEFAULTS when OT.conf is not available.
      #
      # @return [Hash<Symbol, String>] Global brand settings with config overrides
      def self.global_defaults
        return GLOBAL_DEFAULTS unless defined?(OT) && OT.respond_to?(:conf) && OT.conf

        brand_conf = OT.conf['brand'] || {}
        {
          support_email: brand_conf['support_email'] || GLOBAL_DEFAULTS[:support_email],
          product_name: brand_conf['product_name'] || GLOBAL_DEFAULTS[:product_name],
          totp_issuer: brand_conf['totp_issuer'] || GLOBAL_DEFAULTS[:totp_issuer],
          logo_url: brand_conf['logo_url'] || GLOBAL_DEFAULTS[:logo_url],
        }
      end

      BOOLEAN_FIELDS = %w[
        allow_public_homepage
        allow_public_api
        button_text_light
        passphrase_required
        notify_enabled
      ].freeze

      FONTS   = %w[sans serif mono].freeze
      CORNERS = %w[rounded square pill].freeze
    end

    BrandSettings = Data.define(
      :logo,
      :primary_color,
      :product_name,
      :product_domain,
      :support_email,
      :footer_text,
      :description,
      :logo_url,
      :logo_dark_url,
      :favicon_url,
      :instructions_pre_reveal,
      :instructions_reveal,
      :instructions_post_reveal,
      :button_text_light,
      :font_family,
      :corner_style,
      :allow_public_homepage,
      :allow_public_api,
      :locale,
      :default_ttl,
      :passphrase_required,
      :notify_enabled,
    ) do
      include BrandSettingsConstants

      # Creates a BrandSettings instance from a hash, applying defaults.
      # All unspecified members default to nil except those in DEFAULTS.
      # Coerces string "true"/"false" to booleans for boolean fields.
      #
      # @param hash [Hash, nil] Input hash with string or symbol keys
      # @return [BrandSettings] New immutable instance
      def self.from_hash(hash)
        hash     ||= {}
        normalized = hash.transform_keys(&:to_sym).slice(*members)

        # Coerce boolean fields from strings to actual booleans
        BrandSettingsConstants::BOOLEAN_FIELDS.each do |field|
          field_sym = field.to_sym
          next unless normalized.key?(field_sym)

          normalized[field_sym] = coerce_boolean(normalized[field_sym])
        end

        # Build full hash with nil defaults for all members, then apply defaults, then user values
        all_nil = members.each_with_object({}) { |m, h| h[m] = nil }
        new(**all_nil, **BrandSettingsConstants.defaults, **normalized)
      end

      # Coerces a value to boolean
      # @param value [Object] Value to coerce
      # @return [Boolean, nil] Coerced boolean or nil
      def self.coerce_boolean(value)
        return nil if value.nil?
        return value if [true, false].include?(value)

        value.to_s == 'true'
      end

      # Validates a hash of brand settings, raising on invalid values.
      # Intended for write paths (API endpoints) to enforce strict input.
      # Does NOT validate on read (from_hash remains tolerant for existing Redis data).
      #
      # Only validates fields that are present in the hash; missing fields are not errors.
      #
      # @param hash [Hash] Input hash with string or symbol keys
      # @raise [Onetime::Problem] If any provided value is invalid
      # @return [void]
      def self.validate!(hash)
        return if hash.nil? || hash.empty?

        normalized = hash.transform_keys(&:to_sym).slice(*members)

        validate_color_field!(normalized)
        validate_color_accessibility!(normalized)
        validate_font_field!(normalized)
        validate_corner_style_field!(normalized)
        validate_url_fields!(normalized)
        validate_ttl_field!(normalized)
      end

      # @api private
      def self.validate_color_field!(normalized)
        return unless normalized.key?(:primary_color) && !normalized[:primary_color].nil?
        return if valid_color?(normalized[:primary_color])

        raise Onetime::Problem, 'Invalid primary color format - must be hex code (e.g. #FF0000)'
      end

      # @api private
      def self.validate_color_accessibility!(normalized)
        return unless normalized.key?(:primary_color) && !normalized[:primary_color].nil?

        color          = normalized[:primary_color]
        white_contrast = contrast_ratio(color, '#FFFFFF')

        # WCAG AA requires 3:1 for large text, 4.5:1 for normal text
        # We validate against white background (primary UI use case)
        min_contrast = 3.0 # Large text minimum

        return if white_contrast >= min_contrast

        raise Onetime::Problem,
          "Color #{color} fails WCAG AA accessibility - contrast #{white_contrast.round(2)}:1 with white " \
          '(minimum 3:1 for large text, 4.5:1 for normal text). ' \
          'Try a darker shade or use an online contrast checker.'
      end

      # @api private
      def self.validate_font_field!(normalized)
        return unless normalized.key?(:font_family) && !normalized[:font_family].nil?
        return if valid_font?(normalized[:font_family])

        raise Onetime::Problem, "Invalid font family - must be one of: #{BrandSettingsConstants::FONTS.join(', ')}"
      end

      # @api private
      def self.validate_corner_style_field!(normalized)
        return unless normalized.key?(:corner_style) && !normalized[:corner_style].nil?
        return if valid_corner_style?(normalized[:corner_style])

        raise Onetime::Problem, "Invalid corner style - must be one of: #{BrandSettingsConstants::CORNERS.join(', ')}"
      end

      # @api private
      def self.validate_url_fields!(normalized)
        [:logo_url, :logo_dark_url, :favicon_url].each do |url_field|
          next unless normalized.key?(url_field) && !normalized[url_field].nil?
          next if valid_url?(normalized[url_field])

          raise Onetime::Problem, "Invalid #{url_field.to_s.tr('_', ' ')} - must be https:// URL or relative path starting with /"
        end
      end

      # @api private
      def self.validate_ttl_field!(normalized)
        return unless normalized.key?(:default_ttl) && !normalized[:default_ttl].nil?

        ttl = normalized[:default_ttl]
        begin
          ttl = Integer(ttl, 10) if ttl.is_a?(String)
        rescue ArgumentError
          raise Onetime::Problem, 'Invalid default TTL - must be a positive integer (seconds)'
        end
        return if ttl.is_a?(Integer) && ttl.positive?

        raise Onetime::Problem, 'Invalid default TTL - must be a positive integer (seconds)'
      end

      # Validates a hex color string.
      #
      # @param color [String, nil] Color to validate
      # @return [Boolean] true if valid hex color
      def self.valid_color?(color)
        return false if color.nil? || color.empty?

        color.match?(/^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/)
      end

      # Normalizes a hex color to 6-digit form.
      # Expands 3-digit shorthand (#F00 -> #FF0000) and uppercases.
      # Returns nil for invalid colors.
      #
      # @param color [String, nil] Color to normalize
      # @return [String, nil] Normalized 6-digit hex color or nil
      def self.normalize_color(color)
        return nil unless valid_color?(color)

        hex = color.delete('#')
        hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
        "##{hex.upcase}"
      end

      # Calculates WCAG 2.1 contrast ratio between two colors.
      # Formula: https://www.w3.org/WAI/GL/wiki/Contrast_ratio
      #
      # @param color1 [String] First hex color
      # @param color2 [String] Second hex color
      # @return [Float] Contrast ratio (1.0 to 21.0)
      def self.contrast_ratio(color1, color2)
        l1 = relative_luminance(color1)
        l2 = relative_luminance(color2)

        lighter = [l1, l2].max
        darker  = [l1, l2].min

        (lighter + 0.05) / (darker + 0.05)
      end

      # Calculates relative luminance for WCAG contrast formula.
      # Uses ITU-R BT.709 coefficients with sRGB gamma correction.
      #
      # @param hex_color [String] Hex color code
      # @return [Float] Relative luminance (0.0 to 1.0)
      def self.relative_luminance(hex_color)
        hex = hex_color.delete('#')
        hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3

        r, g, b = [hex[0..1], hex[2..3], hex[4..5]].map { |c| c.to_i(16) / 255.0 }

        # Apply sRGB gamma correction
        rgb = [r, g, b].map do |v|
          v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055)**2.4
        end

        # Calculate relative luminance using ITU-R BT.709 coefficients
        (0.2126 * rgb[0]) + (0.7152 * rgb[1]) + (0.0722 * rgb[2])
      end

      # Validates a font family string.
      #
      # @param font [String, nil] Font to validate
      # @return [Boolean] true if valid font family
      def self.valid_font?(font)
        return false if font.nil?

        BrandSettingsConstants::FONTS.include?(font.to_s.downcase)
      end

      # Validates a corner style string.
      #
      # @param style [String, nil] Style to validate
      # @return [Boolean] true if valid corner style
      def self.valid_corner_style?(style)
        return false if style.nil?

        BrandSettingsConstants::CORNERS.include?(style.to_s.downcase)
      end

      # Validates a URL string for logo/favicon fields.
      # Accepts https:// URLs or relative paths starting with /.
      # Enforces max length of 2048 chars to prevent abuse.
      #
      # @param url [String, nil] URL to validate
      # @return [Boolean] true if valid URL
      def self.valid_url?(url)
        return false if url.nil? || url.empty?
        return false if url.length > 2048

        # Reject protocol-relative URLs (//)
        return false if url.start_with?('//')

        # Allow relative paths starting with / (but not //)
        return true if url.start_with?('/')

        # Require https:// for absolute URLs with valid host
        begin
          uri = URI.parse(url)
          return false unless uri.is_a?(URI::HTTPS)
          return false if uri.host.nil? || uri.host.empty?

          true
        rescue URI::InvalidURIError
          false
        end
      end

      # Converts to a hash suitable for Redis storage.
      # JSON-encodes values like Familia::Horreum#to_h_for_storage.
      # Excludes nil values to optimize storage.
      #
      # @return [Hash<String, String>] Hash with string keys and JSON-encoded values
      def to_h_for_storage
        to_h.compact.transform_keys(&:to_s).transform_values do |val|
          Familia::JsonSerializer.dump(val)
        end
      end

      # @return [Boolean] Whether public homepage is allowed
      def allow_public_homepage?
        allow_public_homepage == true
      end

      # @return [Boolean] Whether public API is allowed
      def allow_public_api?
        allow_public_api == true
      end

      # @return [Boolean] Whether passphrase is required by default
      def passphrase_required?
        passphrase_required == true
      end

      # @return [Boolean] Whether notifications are enabled by default
      def notify_enabled?
        notify_enabled == true
      end
    end

    # Re-export constants at BrandSettings level for convenient access
    BrandSettings::DEFAULTS = BrandSettingsConstants::DEFAULTS
    BrandSettings::FONTS    = BrandSettingsConstants::FONTS
    BrandSettings::CORNERS  = BrandSettingsConstants::CORNERS
  end
end
