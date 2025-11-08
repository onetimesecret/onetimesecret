# .purgatory/apps-api-v1/logic/helpers/i18n.rb
#
# frozen_string_literal: true

module V1
  module Logic
    module I18nHelpers

      # Retrieves and caches localized content for the current locale with fallback behavior.
      #
      # This implementation uses per-locale caching to prevent state conflicts when
      # the locale changes between method calls.
      #
      # @note PRODUCTION VS TESTING IMPACT:
      #   In production, each Logic instance typically handles a single request with
      #   consistent locale, so simple memoization rarely causes issues.
      #
      #   In testing, the same Logic instance may be reused with different locales
      #   or test execution order becomes significant, causing intermittent failures
      #   when locales change or invalid locales are tested first.
      #
      # @return [Hash] Localized content with keys:
      #   - :locale [String] The resolved locale code
      #   - :email [Hash] Email translation content
      #   - :web [Hash] Web UI translation content
      #
      def i18n
        locale = self.locale #|| OT.default_locale || 'en'
        @i18n_cache ||= {}

        # Return cached value for this specific locale if it exists
        return @i18n_cache[locale] if @i18n_cache.key?(locale)

        # Safely get locale data with fallback
        locale_data = OT.locales[locale] || OT.locales['en'] || {}

        # Create the i18n data
        result = {
          locale: locale,
          email: locale_data[:email] || {},
          web: locale_data[:web] || {},
        }

        # Cache for this specific locale
        @i18n_cache[locale] = result

        result
      end

    end
  end
end
