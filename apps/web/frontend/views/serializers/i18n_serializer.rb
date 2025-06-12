# apps/web/frontend/views/serializers/i18n_serializer.rb

module Frontend
  module Views
    # Serializes internationalization data for the frontend
    #
    # Responsible for providing locale configuration, available locales,
    # and other i18n-related settings to the frontend.
    module I18nSerializer
      # Serializes internationalization data from view variables
      #
      # @param view_vars [Hash] The view variables containing locale information
      # @param i18n [Object] The internationalization instance
      # @return [Hash] Serialized i18n configuration including locale settings
      def self.serialize(view_vars, _i18n)
        output = self.output_template

        output[:locale]            = view_vars&.fetch(:locale, nil)
        output[:default_locale]    = OT.default_locale # the application default
        output[:fallback_locale]   = OT.fallback_locale
        output[:supported_locales] = OT.supported_locales
        output[:i18n_enabled]      = OT.i18n_enabled

        output
      end

      class << self
        # Provides the base template for i18n serializer output
        #
        # @return [Hash] Template with all possible i18n output fields
        def output_template
          {
            locale: nil,
            default_locale: nil,
            fallback_locale: nil,
            supported_locales: [],
            i18n_enabled: nil,
          }
        end
      end

      SerializerRegistry.register(self, ['DomainSerializer'])
    end
  end
end
