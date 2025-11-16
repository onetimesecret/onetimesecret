# lib/onetime/initializers/load_locales.rb
#
# frozen_string_literal: true

require 'familia/json_serializer'

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

      OT.ld '[init] Parsing through i18n locales...'

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

      # Iterate over the list of supported locales, to load their JSON
      # Supports both split locale directories (new) and monolithic files (legacy)
      confs = OT.supported_locales.collect do |loc|
        locale_dir = File.join(Onetime::HOME, 'src', 'locales', loc)
        locale_file = File.join(Onetime::HOME, 'src', 'locales', "#{loc}.json")

        # Check if this locale uses the new split directory structure
        if Dir.exist?(locale_dir)
          # Glob all JSON files in deterministic order (alphabetical)
          json_files = Dir.glob(File.join(locale_dir, '*.json')).sort

          if json_files.empty?
            OT.le "[init] No JSON files found in locale directory: #{locale_dir}"
            next
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
        elsif File.exist?(locale_file)
          # Legacy: single monolithic file
          OT.ld "[init] Loading #{loc}: monolithic file"
          begin
            contents = File.read(locale_file)
            conf = Familia::JsonSerializer.parse(contents, symbolize_names: true)
            [loc, conf]
          rescue Errno::ENOENT
            OT.le "[init] Missing locale file: #{locale_file}"
            next
          rescue JSON::ParserError => e
            OT.le "[init] JSON parse error: #{locale_file} - #{e.message}"
            next
          end
        else
          OT.le "[init] Missing locale: #{loc} (no directory or file found)"
          next
        end
      end

      # Convert the zipped array to a hash
      locales_defs = confs.compact.to_h

      default_locale_def = locales_defs.fetch(OT.default_locale, {})

      # Here we overlay each locale on top of the default just
      # in case there are keys that haven't been translated.
      # That way, at least the default language will display.
      locales_defs.each do |key, locale|
        next if OT.default_locale == key

        locales_defs[key] = OT::Utils.deep_merge(default_locale_def, locale)
      end

      @locales = locales_defs || {}
    end
  end
end
