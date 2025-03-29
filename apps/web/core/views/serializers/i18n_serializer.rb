# apps/web/core/views/serializers/i18n_serializer.rb

module Core
  module Views
    module I18nSerializer
        # - i18n_enabled, locale, is_default_locale, supported_locales, fallback_locale, default_locale
      def self.serialize(vars, i18n)
        self[:jsvars][:locale] = jsvar(display_locale) # the locale the user sees
        self[:jsvars][:is_default_locale] = jsvar(is_default_locale)
        self[:jsvars][:default_locale] = jsvar(OT.default_locale) # the application default
        self[:jsvars][:fallback_locale] = jsvar(OT.fallback_locale)
        self[:jsvars][:supported_locales] = jsvar(OT.supported_locales)
        self[:jsvars][:i18n_enabled] = jsvar(OT.i18n_enabled)

      end

      private

      def self.output_template
        {}
      end

    end
  end
end
