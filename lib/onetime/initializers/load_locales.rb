# lib/onetime/initializers/load_locales.rb

require 'json'
require 'onetime/refinements/hash_refinements'

module Onetime
  module Initializers
    module LoadLocales

      using IndifferentHashAccess

      def self.run(options = {})
        i18n = OT.conf.fetch(:internationalization, {})
        OT.instance_variable_set(:@i18n_enabled, i18n[:enabled] || false)

        OT.ld "Parsing through i18n locales..."

        # Load the locales from the config in both the current and
        # legacy locations. If the locales are not set in the config,
        # we fallback to english.
        locales_list = i18n.fetch(:locales, nil) || OT.conf.fetch(:locales, ['en']).map(&:to_s)

        if OT.i18n_enabled
          # First look for the default locale in the i18n config, then
          # legacy the locales config approach of using the first one.
          supported_locales = locales_list
          default_locale = i18n.fetch(:default_locale, locales_list.first) || 'en'
          fallback_locale = i18n.fetch(:fallback_locale, nil)

          unless locales_list.include?(default_locale)
            OT.le "Default locale #{default_locale} not in locales_list #{locales_list}"
            OT.instance_variable_set(:@i18n_enabled, false)
          end
        else
          default_locale = 'en'
          supported_locales = [default_locale]
          fallback_locale = nil
        end

        OT.instance_variable_set(:@supported_locales, supported_locales)
        OT.instance_variable_set(:@default_locale, default_locale)
        OT.instance_variable_set(:@fallback_locale, fallback_locale)

        # Iterate over the list of supported locales, to load their JSON
        confs = supported_locales.collect do |loc|
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

        default_locale_def = locales_defs.fetch(default_locale, {})

        # Here we overlay each locale on top of the default just
        # in case there are keys that haven't been translated.
        # That way, at least the default language will display.
        locales_defs.each do |key, locale|
          next if default_locale == key
          # NOTE: We switched to using the properly deep merge method from utils
          # which avoids potential accidental modification of child hashes. It
          # also treats nils differently, ensuring that the default values are
          # preserved when merging and nils no longer override existing values.
          locales_defs[key] = OT::Utils.deep_merge(default_locale_def, locale)
        end

        # Allow indifferent access to the locales hash
        OT.instance_variable_set(:@locales, locales_defs || {})

        OT.ld "[initializer] Locales loaded (i18n enabled: #{OT.i18n_enabled})"
      end

    end
  end
end
