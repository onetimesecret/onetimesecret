# lib/onetime/initializers/load_locales.rb
#
# frozen_string_literal: true

require 'i18n'

module Onetime
  module Initializers
    @i18n_enabled = false

    attr_reader :i18n_enabled, :locales, :supported_locales, :default_locale, :fallback_locale

    # We always load locales regardless of whether internationalization
    # is enabled. When it's disabled, we just limit the locales to
    # english. Otherwise we would have to text strings to use.
    def load_locales
      i18n          = OT.conf.fetch('internationalization', {})
      @i18n_enabled = i18n['enabled'] || false

      OT.ld '[init] Configuring ruby-i18n gem...'

      # Load the locales from the config in both the current and
      # legacy locations. If the locales are not set in the config,
      # we fallback to english.
      locales_list = i18n.fetch('locales', nil) || OT.conf.fetch('locales', ['en']).map(&:to_s)

      if OT.i18n_enabled
        # First look for the default locale in the i18n config, then
        # legacy the locales config approach of using the first one.
        @supported_locales = locales_list
        @default_locale    = i18n.fetch('default_locale', locales_list.first) || 'en'
        @fallback_locale   = i18n.fetch('fallback_locale', nil)

        unless locales_list.include?(OT.default_locale)
          OT.le "[init] Default locale #{OT.default_locale} not in locales_list #{locales_list}"
          @i18n_enabled = false
        end
      else
        @default_locale    = 'en'
        @supported_locales = [OT.default_locale]
        @fallback_locale   = nil
      end

      # Configure I18n gem to use existing JSON locale files
      # Note: JSON is valid YAML, so I18n can load .json files directly
      I18n.load_path = Dir[File.join(Onetime::HOME, 'src', 'locales', '*.json')]
      I18n.default_locale = @default_locale.to_sym
      I18n.available_locales = @supported_locales.map(&:to_sym)

      # Set up fallbacks if configured
      if @fallback_locale && I18n.respond_to?(:fallbacks)
        require 'i18n/backend/fallbacks'
        I18n::Backend::Simple.send(:include, I18n::Backend::Fallbacks)

        if @fallback_locale.is_a?(Hash)
          I18n.fallbacks = @fallback_locale.transform_keys(&:to_sym).transform_values { |v| v.map(&:to_sym) }
        else
          OT.ld "[init] Fallback locale configured as: #{@fallback_locale}"
        end
      end

      OT.ld "[init] I18n configured with default locale: #{I18n.default_locale}"
      OT.ld "[init] I18n available locales: #{I18n.available_locales.join(', ')}"

      # For backward compatibility, maintain the @locales hash
      # by loading all locale data into a hash structure similar to before
      @locales = {}
      OT.supported_locales.each do |locale|
        @locales[locale] = load_locale_hash(locale.to_sym)
      end

      OT.ld "[init] Loaded #{@locales.keys.size} locales"
    end

    private

    # Helper method to load locale data into a hash for backward compatibility
    def load_locale_hash(locale)
      old_locale = I18n.locale
      begin
        I18n.locale = locale

        # Load the entire locale tree
        locale_data = {}
        %i[web email].each do |section|
          locale_data[section] = load_section(locale, section)
        end

        locale_data
      rescue StandardError => e
        OT.le "[init] Error loading locale #{locale}: #{e.message}"
        {}
      ensure
        I18n.locale = old_locale
      end
    end

    def load_section(locale, section)
      # Try to load the section, returning empty hash if it doesn't exist
      I18n.t(section, locale: locale, default: {})
    end
  end
end
