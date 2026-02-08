# lib/onetime/models/custom_domain/brand_settings.rb
#
# frozen_string_literal: true

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
        button_text_light: false,
        allow_public_homepage: false,
        allow_public_api: false,
        default_ttl: nil,
        passphrase_required: false,
        notify_enabled: false,
      }.freeze

      # Returns defaults with primary_color resolved from brand config.
      # Falls back to DEFAULTS when OT.conf is not available.
      def self.defaults
        color = if defined?(OT) && OT.respond_to?(:conf) && OT.conf
                  OT.conf.dig('brand', 'primary_color')
                end
        DEFAULTS.merge(primary_color: color || DEFAULTS[:primary_color])
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

      # Validates a hex color string.
      #
      # @param color [String, nil] Color to validate
      # @return [Boolean] true if valid hex color
      def self.valid_color?(color)
        return false if color.nil? || color.empty?

        color.match?(/^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3})$/)
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
