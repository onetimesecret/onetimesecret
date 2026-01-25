# lib/onetime/initializers/load_locales.rb
#
# frozen_string_literal: true

require 'familia/json_serializer'

module Onetime
  module Initializers
    # LoadLocales initializer
    #
    # Loads and configures internationalization (i18n) support. Parses locale
    # JSON files from generated/locales/{locale}.json (pre-merged by the
    # sync script).
    #
    # Runtime state set:
    # - Onetime::Runtime.internationalization.enabled
    # - Onetime::Runtime.internationalization.supported_locales
    # - Onetime::Runtime.internationalization.default_locale
    # - Onetime::Runtime.internationalization.fallback_locale
    # - Onetime::Runtime.internationalization.locales
    #
    class LoadLocales < Onetime::Boot::Initializer
      @provides = [:i18n]

      LOCALES_ROOT = File.join(Onetime::HOME, 'generated', 'locales')

      def execute(_context)
        start_time   = OT.now_in_μs
        i18n         = OT.conf.fetch('internationalization', {})
        i18n_enabled = i18n['enabled'] || false

        OT.boot_logger.debug '[i18n] Parsing through i18n locales...'

        # Load the locales from the config in both the current and
        # legacy locations. If the locales are not set in the config,
        # we fallback to english.
        locales_list = i18n.fetch('locales', nil) || OT.conf.fetch('locales', ['en']).map(&:to_s)

        if i18n_enabled
          supported_locales, default_locale, fallback_locale = extract_i18n_config(i18n, locales_list)

          # Validate default locale is in supported list
          unless locales_list.include?(default_locale)
            OT.le "[i18n] Default locale #{default_locale} not in locales_list #{locales_list}"
            i18n_enabled = false
            # Fall through to disabled path below
          end
        end

        # If i18n is disabled or validation failed, use english-only
        unless i18n_enabled
          supported_locales = ['en']
          default_locale    = 'en'
          fallback_locale   = nil
        end

        # Load locale definitions from filesystem
        locales_defs = load_locale_definitions(supported_locales, default_locale)

        # Set runtime state
        Onetime::Runtime.internationalization = Onetime::Runtime::Internationalization.new(
          enabled: i18n_enabled,
          supported_locales: supported_locales,
          default_locale: default_locale,
          fallback_locale: fallback_locale,
          locales: locales_defs,
        )

        elapsed = (OT.now_in_μs - start_time) / 1000.0
        OT.info "[i18n] i18n initialization took #{elapsed.round(2)}ms"
      end

      private

      def extract_i18n_config(i18n, locales_list)
        # First look for the default locale in the i18n config, then
        # legacy the locales config approach of using the first one.
        supported = locales_list
        default   = i18n.fetch('default_locale', locales_list.first) || 'en'
        fallback  = i18n.fetch('fallback_locale', nil)

        [supported, default, fallback]
      end

      def load_locale_definitions(supported_locales, default_locale)
        locales_defs = load_all_locales_from_source(supported_locales)
        apply_default_locale_fallback(locales_defs, default_locale)
        locales_defs || {}
      end

      def load_all_locales_from_source(supported_locales)
        supported_locales.each_with_object({}) do |loc, hash|
          locale_file = File.join(LOCALES_ROOT, "#{loc}.json")

          unless File.exist?(locale_file)
            OT.le "[i18n] Missing locale file: #{locale_file}"
            next
          end

          OT.ld "[i18n] Loading #{loc}: #{locale_file}"
          contents  = File.read(locale_file)
          hash[loc] = Familia::JsonSerializer.parse(contents, symbolize_names: false)
        rescue Errno::ENOENT => ex
          OT.le "[i18n] File read error: #{locale_file} - #{ex.message}"
        rescue JSON::ParserError => ex
          OT.le "[i18n] JSON parse error: #{locale_file} - #{ex.message}"
        end
      end

      def apply_default_locale_fallback(locales_defs, default_locale)
        default_locale_def = locales_defs.fetch(default_locale, {})

        # Here we overlay each locale on top of the default just
        # in case there are keys that haven't been translated.
        # That way, at least the default language will display.
        locales_defs.each do |key, locale|
          next if default_locale == key

          locales_defs[key] = OT::Utils.deep_merge(default_locale_def, locale)
        end
      end
    end
  end
end
