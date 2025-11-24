# lib/onetime/initializers/load_locales.rb
#
# frozen_string_literal: true

require 'familia/json_serializer'

module Onetime
  module Initializers
    # LoadLocales initializer
    #
    # Loads and configures internationalization (i18n) support. Parses locale
    # JSON files and sets up locale fallback chain. Supports both split
    # directory structure (src/locales/en/*.json) and legacy monolithic files
    # (src/locales/en.json).
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

      def execute(_context)
        i18n = OT.conf.fetch('internationalization', {})
        i18n_enabled = i18n['enabled'] || false

        OT.ld '[init] Parsing through i18n locales...'

        # Load the locales from the config in both the current and
        # legacy locations. If the locales are not set in the config,
        # we fallback to english.
        locales_list = i18n.fetch('locales', nil) || OT.conf.fetch('locales', ['en']).map(&:to_s)

        if i18n_enabled
          supported_locales, default_locale, fallback_locale = extract_i18n_config(i18n, locales_list)

          # Validate default locale is in supported list
          unless locales_list.include?(default_locale)
            OT.le "[init] Default locale #{default_locale} not in locales_list #{locales_list}"
            i18n_enabled = false
            # Fall through to disabled path below
          end
        end

        # If i18n is disabled or validation failed, use english-only
        unless i18n_enabled
          supported_locales = ['en']
          default_locale = 'en'
          fallback_locale = nil
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
      end

      private

      def extract_i18n_config(i18n, locales_list)
        # First look for the default locale in the i18n config, then
        # legacy the locales config approach of using the first one.
        supported = locales_list
        default = i18n.fetch('default_locale', locales_list.first) || 'en'
        fallback = i18n.fetch('fallback_locale', nil)

        [supported, default, fallback]
      end

      def load_locale_definitions(supported_locales, default_locale)
        # Iterate over the list of supported locales, to load their JSON
        # Supports both split locale directories (new) and monolithic files (legacy)
        confs = supported_locales.collect do |loc|
          locale_dir = File.join(Onetime::HOME, 'src', 'locales', loc)
          locale_file = File.join(Onetime::HOME, 'src', 'locales', "#{loc}.json")

          # Check if this locale uses the new split directory structure
          if Dir.exist?(locale_dir)
            load_split_locale(loc, locale_dir)
          elsif File.exist?(locale_file)
            load_monolithic_locale(loc, locale_file)
          else
            OT.le "[init] Missing locale: #{loc} (no directory or file found)"
            next
          end
        end

        # Convert the zipped array to a hash
        locales_defs = confs.compact.to_h

        # Apply fallback overlay
        apply_default_locale_fallback(locales_defs, default_locale)

        locales_defs || {}
      end

      def load_split_locale(loc, locale_dir)
        # Glob all JSON files in deterministic order (alphabetical)
        json_files = Dir.glob(File.join(locale_dir, '*.json')).sort

        if json_files.empty?
          OT.le "[init] No JSON files found in locale directory: #{locale_dir}"
          return nil
        end

        OT.ld "[init] Loading #{loc}: #{json_files.size} split files"

        # Merge all files for this locale, preserving symbol keys
        # We use a custom merge that doesn't normalize keys like deep_merge does
        merged_locale = json_files.each_with_object({}) do |file_path, merged|
          begin
            contents = File.read(file_path)
            parsed   = Familia::JsonSerializer.parse(contents, symbolize_names: true)

            # Manually merge to preserve symbol keys
            parsed.each do |top_key, top_value|
              if merged[top_key].is_a?(Hash) && top_value.is_a?(Hash)
                # Merge nested hashes (e.g., both have :web key)
                merged[top_key] ||= {}
                top_value.each do |nested_key, nested_value|
                  merged[top_key][nested_key] = nested_value
                end
              else
                # Direct assignment for non-hash values
                merged[top_key] = top_value
              end
            end
          rescue Errno::ENOENT => e
            OT.le "[init] File read error: #{file_path} - #{e.message}"
          rescue JSON::ParserError => e
            OT.le "[init] JSON parse error: #{file_path} - #{e.message}"
          end
        end

        [loc, merged_locale]
      end

      def load_monolithic_locale(loc, locale_file)
        # Legacy: single monolithic file
        OT.ld "[init] Loading #{loc}: monolithic file"
        begin
          contents = File.read(locale_file)
          conf = Familia::JsonSerializer.parse(contents, symbolize_names: true)
          [loc, conf]
        rescue Errno::ENOENT
          OT.le "[init] Missing locale file: #{locale_file}"
          nil
        rescue JSON::ParserError => e
          OT.le "[init] JSON parse error: #{locale_file} - #{e.message}"
          nil
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
