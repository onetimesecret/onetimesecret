# apps/web/core/views/serializers/i18n_serializer.rb

module Core
  module Views
    module I18nSerializer
        # - i18n_enabled, locale, is_default_locale, supported_locales, fallback_locale, default_locale
      def self.serialize(view_vars, i18n)
        output = self.output_template

        output[:locale] = view_vars[:locale]
        output[:default_locale] = OT.default_locale # the application default
        output[:fallback_locale] = OT.fallback_locale
        output[:supported_locales] = OT.supported_locales
        output[:i18n_enabled] = OT.i18n_enabled

        output
      end

      private

      def self.output_template
        {
          locale: nil,
          default_locale: nil,
          fallback_locale: nil,
          supported_locales: [],
          i18n_enabled: nil,
        }
      end

      SerializerRegistry.register(self)
    end
  end
end
