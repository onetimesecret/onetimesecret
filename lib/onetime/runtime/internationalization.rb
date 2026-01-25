# lib/onetime/runtime/internationalization.rb
#
# frozen_string_literal: true

module Onetime
  module Runtime
    # Internationalization (i18n) runtime state
    #
    # Holds locale configuration and loaded locale data set during boot.
    # This state is immutable after initialization and thread-safe.
    #
    # Set by: LoadLocales initializer
    #
    Internationalization = Data.define(
      :enabled,             # Whether i18n is enabled
      :supported_locales,   # Array of supported locale codes (e.g., ['en', 'es', 'fr'])
      :default_locale,      # Default locale code (e.g., 'en')
      :fallback_locale,     # Fallback locale when translation missing
      :locales,             # Hash of loaded locale definitions
    ) do
      # Factory method for default state
      #
      # @return [Internationalization] Internationalization state with safe defaults
      #
      def self.default
        new(
          enabled: false,
          supported_locales: [],
          default_locale: 'en',
          fallback_locale: 'en',
          locales: {},
        )
      end

      # Check if a specific locale is supported
      #
      # @param locale [String, Symbol] Locale code to check
      # @return [Boolean] true if locale is supported
      #
      def supports?(locale)
        supported_locales.include?(locale.to_s)
      end

      # Get locale data for a specific locale
      #
      # @param locale [String, Symbol] Locale code
      # @return [Hash, nil] Locale data or nil if not found
      #
      def locale_data(locale)
        locales[locale.to_s]
      end

      # Get number of loaded locales
      #
      # @return [Integer] Count of loaded locales
      #
      def locale_count
        locales.size
      end
    end
  end
end
