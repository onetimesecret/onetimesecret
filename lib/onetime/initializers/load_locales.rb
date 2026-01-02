# lib/onetime/initializers/load_locales.rb
#
# frozen_string_literal: true

require 'familia/json_serializer'
require 'digest'
require 'fileutils'

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

      LOCALES_ROOT       = File.join(Onetime::HOME, 'src', 'locales')
      CACHE_FILE_PATTERN = '.all-locales-*.cache'

      def self.cleanup_caches
        Dir.glob(File.join(LOCALES_ROOT, CACHE_FILE_PATTERN)).each do |cache_path|
          warn "[i18n] Removing #{cache_path}"
          File.delete(cache_path)
        rescue StandardError => ex
          OT.le "[i18n] Error removing cache #{cache_path}: #{ex.message}"
        end
      end

      def self.precompile
        instance       = new
        i18n           = OT.conf.fetch('internationalization', {})
        locales_list   = i18n.fetch('locales', nil) || OT.conf.fetch('locales', ['en']).map(&:to_s)
        default_locale = i18n.fetch('default_locale', locales_list.first) || 'en'

        Onetime.log_box(['[i18n] Precompiling locales'])

        OT.ld "[i18n] Locales list: #{locales_list}"

        # Use the same code path as runtime - this will create the cache
        instance.send(:load_locale_definitions, locales_list, default_locale)

        OT.info '[i18n] Precompilation complete'
      end

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
        # Try to load from unified cache first
        cache_file = compute_cache_path(supported_locales)

        if cache_file && File.exist?(cache_file)
          OT.log_box(['', '💱 [i18n] Cache hit for locales', ''])

          locales_defs = load_from_cache(cache_file)
          if locales_defs
            cleanup_stale_all_locales_caches(cache_file)
            return locales_defs
          end
        end

        # Cache miss or error - load from source files
        OT.log_box(['', '💱 [i18n] Cache miss for locales', ''])
        locales_defs = load_all_locales_from_source(supported_locales)

        # Apply fallback overlay
        apply_default_locale_fallback(locales_defs, default_locale)

        # Write to unified cache
        if cache_file
          write_all_locales_cache(cache_file, locales_defs)
          cleanup_stale_all_locales_caches(cache_file)
        end

        locales_defs || {}
      end

      def load_all_locales_from_source(supported_locales)
        # Iterate over the list of supported locales, to load their JSON
        # Supports both split locale directories (new) and monolithic files (legacy)
        confs = supported_locales.collect do |loc|
          locale_dir  = File.join(LOCALES_ROOT, loc)
          locale_file = File.join(LOCALES_ROOT, "#{loc}.json")

          # Check if this locale uses the new split directory structure
          if Dir.exist?(locale_dir)
            load_split_locale(loc, locale_dir)
          elsif File.exist?(locale_file)
            load_monolithic_locale(loc, locale_file)
          else
            OT.le "[i18n] Missing locale: #{loc} (no directory or file found)"
            next
          end
        end

        # Convert the zipped array to a hash
        confs.compact.to_h
      end

      def load_split_locale(loc, locale_dir)
        # Glob all JSON files in deterministic order (alphabetical)
        json_files = Dir.glob(File.join(locale_dir, '*.json'))

        if json_files.empty?
          OT.le "[i18n] No JSON files found in locale directory: #{locale_dir}"
          return nil
        end

        OT.ld "[i18n] Loading #{loc}: split directory (#{json_files.size} files)"

        # Merge all files for this locale using string keys for consistency
        merged_locale = json_files.each_with_object({}) do |file_path, merged|
            contents = File.read(file_path)
            parsed   = Familia::JsonSerializer.parse(contents, symbolize_names: false)

            # Manually merge to preserve string keys
            parsed.each do |top_key, top_value|
              if merged[top_key].is_a?(Hash) && top_value.is_a?(Hash)
                # Merge nested hashes (e.g., both have 'web' key)
                merged[top_key] ||= {}
                top_value.each do |nested_key, nested_value|
                  merged[top_key][nested_key] = nested_value
                end
              else
                # Direct assignment for non-hash values
                merged[top_key] = top_value
              end
            end
        rescue Errno::ENOENT => ex
            OT.le "[i18n] File read error: #{file_path} - #{ex.message}"
        rescue JSON::ParserError => ex
            OT.le "[i18n] JSON parse error: #{file_path} - #{ex.message}"
        end

        [loc, merged_locale]
      end

      def load_monolithic_locale(loc, locale_file)
        # Legacy: single monolithic file
        OT.ld "[i18n] Loading #{loc}: monolithic file"
        begin
          contents = File.read(locale_file)
          conf     = Familia::JsonSerializer.parse(contents, symbolize_names: false)
          [loc, conf]
        rescue Errno::ENOENT
          OT.le "[i18n] Missing locale file: #{locale_file}"
          nil
        rescue JSON::ParserError => ex
          OT.le "[i18n] JSON parse error: #{locale_file} - #{ex.message}"
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

      def compute_cache_path(supported_locales)
        # Collect all source files across all locales to create fingerprint
        all_files = []

        supported_locales.each do |loc|
          locale_dir  = File.join(LOCALES_ROOT, loc)
          locale_file = File.join(LOCALES_ROOT, "#{loc}.json")

          if Dir.exist?(locale_dir)
            all_files += Dir.glob(File.join(locale_dir, '*.json'))
          elsif File.exist?(locale_file)
            all_files << locale_file
          end
        end

        return nil if all_files.empty?

        # Create fingerprint based on all file paths and modification times
        fingerprint = all_files.map { |f| "#{f}:#{File.mtime(f).to_i}" }.join('|')
        hash        = Digest::SHA256.hexdigest(fingerprint)
        File.join(LOCALES_ROOT, ".all-locales-#{hash}.cache")
      end

      def load_from_cache(cache_file)
        contents = File.read(cache_file)
        Familia::JsonSerializer.parse(contents, symbolize_names: false)
      rescue StandardError => ex
        OT.le "[i18n] Cache read error: #{ex.message}"
        nil
      end

      def write_all_locales_cache(cache_file, locales_defs)
        File.write(cache_file, Familia::JsonSerializer.dump(locales_defs))
        OT.info "[i18n] Wrote unified cache: #{File.basename(cache_file)}"
      rescue StandardError => ex
        OT.le "[i18n] Cache write error: #{ex.message}"
      end

      def cleanup_stale_all_locales_caches(current_cache_file)
        # Find all cache files in LOCALES_ROOT
        all_caches = Dir.glob(File.join(LOCALES_ROOT, CACHE_FILE_PATTERN))

        # Remove any that are not the current one
        stale_caches = all_caches.reject { |f| f == current_cache_file }

        stale_caches.each do |stale_path|
          OT.ld "[i18n] Removing stale cache: #{File.basename(stale_path)}"
          File.delete(stale_path)
        rescue StandardError => ex
          OT.le "[i18n] Error removing stale cache #{stale_path}: #{ex.message}"
        end
      end
    end
  end
end
