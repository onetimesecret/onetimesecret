# lib/onetime/initializers/setup_i18n.rb
#
# frozen_string_literal: true

require 'i18n'
require 'i18n/backend/fallbacks'
require 'json'

module Onetime
  module Initializers
    # SetupI18n initializer
    #
    # Configures the ruby-i18n gem for backend localization. Loads locale
    # files from src/locales/ (JSON). All translations including email
    # templates are unified in the JSON locale files.
    # Provides thread-safe translation lookup with fallback behavior.
    #
    # Runtime state dependencies:
    # - Onetime::Runtime.internationalization (read)
    #
    # This initializer must run AFTER LoadLocales to access locale configuration.
    #
    class SetupI18n < Onetime::Boot::Initializer
      @requires = [:i18n]
      @provides = [:ruby_i18n]

      def execute(_context)
        # Add JSON backend support to I18n
        I18n::Backend::Simple.include(JsonBackend)
        I18n::Backend::Simple.include(I18n::Backend::Fallbacks)

        # Configure I18n from runtime state
        # IMPORTANT: Set available_locales BEFORE default_locale to avoid InvalidLocale error
        I18n.available_locales = OT.supported_locales.map(&:to_sym)
        I18n.default_locale = OT.default_locale.to_sym
        # Configure per-locale fallbacks: each locale falls back to default
        I18n.fallbacks = I18n::Locale::Fallbacks.new(I18n.default_locale)

        # Clear any existing load paths (for test isolation)
        I18n.load_path.clear

        # Load JSON files from src/locales (includes email translations)
        load_json_locales

        OT.ld "[init] I18n configured: default=#{I18n.default_locale}, " \
              "available=#{I18n.available_locales}, " \
              "load_path=#{I18n.load_path.size} files"
      end

      private

      def load_json_locales
        locale_files = Dir[File.join(Onetime::HOME, 'src/locales/*/*.json')]

        if locale_files.empty?
          OT.le '[init] No JSON locale files found in src/locales/*/*.json'
          return
        end

        # Add each JSON file to load path
        locale_files.each do |file|
          I18n.load_path << file
        end

        OT.ld "[init] Loaded #{locale_files.size} JSON locale files"
      end

      # JSON backend support module for I18n
      #
      # While JSON is valid YAML, I18n's Simple backend dispatches by file
      # extension and doesn't have a .json handler. More importantly, our
      # locale files don't include the locale key at the top level - we
      # infer it from the directory path (e.g., src/locales/en/file.json).
      #
      module JsonBackend
        # Load JSON file and convert to I18n data structure
        #
        # The JSON files in src/locales/ don't include the locale key at the
        # top level (e.g., they have {web: {...}} instead of {en: {web: {...}}}).
        # We detect this and wrap the data with the locale key.
        #
        # I18n expects loader methods to return a tuple: [data, keys_symbolized]
        # where data is a Hash with locale keys at the top level.
        #
        # @param filename [String] Path to JSON file
        # @return [Array<Hash, Boolean>] Tuple of [translations_hash, keys_symbolized]
        #
        def load_json(filename)
          data = JSON.parse(File.read(filename))

          # Infer locale from path: src/locales/en/file.json -> "en"
          if (match = filename.match(%r{/locales/([^/]+)/}))
            locale = match[1]

            # If data doesn't have locale key at top level, wrap it
            unless data.key?(locale)
              data = { locale => data }
            end
          end

          # Return tuple: [data, keys_symbolized]
          # keys_symbolized=false because we're using string keys like YAML
          [data, false]
        rescue JSON::ParserError => e
          raise I18n::InvalidLocaleData.new(filename, e.message)
        end
      end
    end
  end
end
