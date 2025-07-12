# lib/onetime/initializers/load_locales.rb

require 'json'

module Onetime
  module Initializers
    @i18n_enabled = false

    attr_reader :i18n_enabled, :locales, :supported_locales, :default_locale, :fallback_locale

    # We always load locales regardless of whether internationalization
    # is enabled. When it's disabled, we just limit the locales to
    # english. Otherwise we would have to text strings to use.
    def load_locales
      i18n = OT.conf.fetch(:internationalization, {})
      @i18n_enabled = i18n[:enabled] || false

      OT.ld "Parsing through i18n locales..."

      # Load the locales from the config in both the current and
      # legacy locations. If the locales are not set in the config,
      # we fallback to english.
      locales_list = i18n.fetch(:locales, nil) || OT.conf.fetch(:locales, ['en']).map(&:to_s)

      if OT.i18n_enabled
        # First look for the default locale in the i18n config, then
        # legacy the locales config approach of using the first one.
        @supported_locales = locales_list
        @default_locale = i18n.fetch(:default_locale, locales_list.first) || 'en'
        @fallback_locale = i18n.fetch(:fallback_locale, nil)

        unless locales_list.include?(OT.default_locale)
          OT.le "Default locale #{OT.default_locale} not in locales_list #{locales_list}"
          @i18n_enabled = false
        end
      else
        @default_locale = 'en'
        @supported_locales = [OT.default_locale]
        @fallback_locale = nil
      end

      # Iterate over the list of supported locales, to load their JSON
      confs = OT.supported_locales.collect do |loc|
        path = File.join(Onetime::HOME, 'src', 'locales', "#{loc}.json")
        OT.ld "Loading #{loc}: #{File.exist?(path)}"
        begin
          contents = File.read(path)
        rescue Errno::ENOENT => e
          OT.le "Missing locale file: #{path}"
          next
        end
        conf = JSON.parse(contents, symbolize_names: true)
        [loc, conf]
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
