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
    # files from generated/locales/ (JSON). All translations including email
    # templates are unified in the JSON locale files.
    # Provides thread-safe translation lookup with fallback behavior.
    #
    # Runtime state dependencies:
    # - Onetime::Runtime.internationalization (read)
    #
    # This initializer must run AFTER LoadLocales to access locale configuration.
    #
    class SetupI18n < Onetime::Boot::Initializer
      @depends_on = [:i18n]
      @provides   = [:ruby_i18n]

      def execute(_context)
        # Add JSON backend support to I18n
        OT.ld '[init] Including JsonBackend module in I18n::Backend::Simple'
        I18n::Backend::Simple.include(JsonBackend)
        I18n::Backend::Simple.include(I18n::Backend::Fallbacks)

        # Configure I18n from runtime state
        # IMPORTANT: Set available_locales BEFORE default_locale to avoid InvalidLocale error
        I18n.available_locales = OT.supported_locales.map(&:to_sym)
        I18n.default_locale    = OT.default_locale.to_sym
        # Configure per-locale fallbacks: each locale falls back to default
        I18n.fallbacks         = I18n::Locale::Fallbacks.new(I18n.default_locale)

        # Clear any existing load paths (for test isolation)
        I18n.load_path.clear

        # Load JSON files from generated/locales
        load_json_locales

        # Force reload to ensure translations are loaded with our custom JsonBackend.
        # Without this, I18n may have already loaded files with the default load_json
        # method (which doesn't wrap data with locale key from filename).
        OT.ld '[init] Forcing I18n backend reload to apply JsonBackend'
        I18n.backend.reload!
        OT.ld "[init] I18n backend reloaded, translations initialized: #{I18n.backend.initialized?}"

        OT.ld "[init] I18n configured: default=#{I18n.default_locale}, " \
              "available=#{I18n.available_locales}, " \
              "load_path=#{I18n.load_path.size} files"
      end

      private

      def load_json_locales
        locale_files = Dir[File.join(Onetime::HOME, 'generated/locales/*.json')]

        if locale_files.empty?
          OT.le '[init] No JSON locale files found in generated/locales/*.json'
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
      # infer it from the filename (e.g., generated/locales/en.json).
      #
      module JsonBackend
        # Load JSON file and convert to I18n data structure
        #
        # The JSON files in generated/locales/ don't include the locale key at the
        # top level (e.g., they have {web: {...}} instead of {en: {web: {...}}}).
        # We detect this and wrap the data with the locale key inferred from
        # the filename.
        #
        # I18n expects loader methods to return a tuple: [data, keys_symbolized]
        # where data is a Hash with locale keys at the top level.
        #
        # @param filename [String] Path to JSON file
        # @return [Array<Hash, Boolean>] Tuple of [translations_hash, keys_symbolized]
        #
        def load_json(filename)
          # Defense in depth: validate path before reading to prevent traversal
          locales_dir   = Onetime::HOME.join('generated', 'locales').to_s
          expanded_path = File.expand_path(filename)
          unless expanded_path.start_with?(locales_dir + File::SEPARATOR)
            raise I18n::InvalidLocaleData.new(filename, 'path outside allowed locales directory')
          end

          data = JSON.parse(File.read(expanded_path))

          # Infer locale from filename: generated/locales/en.json -> "en"
          locale = File.basename(expanded_path, '.json')

          # If data doesn't have locale key at top level, wrap it
          wrapped = !data.key?(locale)
          data    = { locale => data } if wrapped

          OT.ld "[i18n] Loaded #{filename} (locale=#{locale}, wrapped=#{wrapped}, keys=#{data[locale]&.keys&.size || 0})"

          # Return tuple: [data, keys_symbolized]
          # keys_symbolized=false because we're using string keys like YAML
          [data, false]
        rescue JSON::ParserError => ex
          raise I18n::InvalidLocaleData.new(filename, ex.message)
        end
      end
    end
  end
end
