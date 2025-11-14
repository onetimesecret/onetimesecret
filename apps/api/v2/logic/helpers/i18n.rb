# apps/api/v2/logic/helpers/i18n.rb
#
# frozen_string_literal: true

module V2
  module Logic
    module I18nHelpers
      # Retrieves and caches localized content for the current locale using
      # ruby-i18n gem with fallback behavior.
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
        locale        = self.locale # || OT.default_locale || 'en'
        @i18n_cache ||= {}

        # Return cached value for this specific locale if it exists
        return @i18n_cache[locale] if @i18n_cache.key?(locale)

        # Set the I18n locale
        I18n.locale = locale.to_sym

        # Get translations using I18n.t with fallback support
        email_messages = I18n.t('email', locale: locale, default: {})
        web_messages = I18n.t('web', locale: locale, default: {})

        # Create the i18n data
        result = {
          locale: locale,
          email: email_messages,
          web: web_messages,
        }

        # Cache for this specific locale
        @i18n_cache[locale] = result

        result
      end
    end
  end
end
