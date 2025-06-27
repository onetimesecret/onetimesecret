# lib/onetime/services/system/load_locales.rb

require_relative '../../refinements/indifferent_hash_access'
require_relative '../service_provider'

module Onetime
  module Services
    module System
      ##
      # Locale Provider
      #
      # Loads and configures internationalization (i18n) support based on
      # the i18n configuration section. Loads locale files and sets up
      # default/fallback locales.
      #
      class LocaleProvider < ServiceProvider
        using Onetime::IndifferentHashAccess

        attr_reader :locales, :default_locale, :fallback_locale, :i18n_enabled

        def initialize
          super(:locales, type: TYPE_INSTANCE, priority: 20)
        end

        ##
        # Load and configure locales from configuration
        #
        # We always load locales regardless of whether internationalization
        # is enabled. When it's disabled, we just limit the locales to
        # english. Otherwise we would have to text strings to use.
        #
        # @param config [Hash] Application configuration
        def start(config)
          debug('Loading internationalization settings...')

          i18n_config   = config.fetch(:i18n, {})
          @i18n_enabled = i18n_config[:enabled] || false

          debug('Parsing through i18n locales...')

          # Load the locales from the config in both the current and
          # legacy locations. If the locales are not set in the config,
          # we fallback to english.
          locales_list = i18n_config.fetch(:locales, ['en']).map(&:to_s)

          if @i18n_enabled
            # First look for the default locale in the i18n config, then
            # legacy the locales config approach of using the first one.
            @supported_locales = locales_list
            @default_locale    = i18n_config.fetch(:default_locale, locales_list.first) || 'en'
            @fallback_locale   = i18n_config.fetch(:fallback_locale, nil)

            unless locales_list.include?(@default_locale)
              error("Default locale #{@default_locale} not in locales_list #{locales_list}")
              @i18n_enabled = false
            end
          else
            @default_locale    = 'en'
            @supported_locales = [@default_locale]
            @fallback_locale   = nil
          end

          # Load locale definitions from JSON files
          @locales = load_locale_definitions(@supported_locales)

          # Register with ServiceRegistry
          register_provider(:locale_service, self)

          # Set global state for backward compatibility. Thanks to the
          # ConfigProxy, these are available via OT.conf[:i18n_enabled]
          set_state(:i18n_enabled, @i18n_enabled)
          set_state(:locales, @locales)
          set_state(:supported_locales, @supported_locales)
          set_state(:default_locale, @default_locale)
          set_state(:fallback_locale, @fallback_locale)

          debug("Loaded #{@locales.size} locale(s): #{@supported_locales.join(', ')}")
        end

        private

        def load_locale_definitions(supported_locales)
          # Load JSON files for each supported locale
          confs = supported_locales.collect do |loc|
            path = File.join(Onetime::HOME, 'src', 'locales', "#{loc}.json")
            debug("Loading #{loc}: #{File.exist?(path)}")

            conf = OT::Configurator::Load.json_load_file(path, symbolize_names: true)

            [loc, conf]
          end

          # Convert the zipped array to a hash
          locales_defs       = confs.compact.to_h
          default_locale_def = locales_defs.fetch(@default_locale, {})

          # Here we overlay each locale on top of the default just
          # in case there are keys that haven't been translated.
          # That way, at least the default language will display.
          locales_defs.each do |key, locale|
            next if @default_locale == key

            locales_defs[key] = OT::Utils.deep_merge(default_locale_def, locale)
          end

          locales_defs
        end
      end

    end
  end
end
