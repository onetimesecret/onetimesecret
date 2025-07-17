# apps/web/manifold/views/helpers/i18n.rb

# I18nHelpers provides localization functionality for view templates.
#
# This module implements a caching mechanism for translations with
# fallback behavior when requested locales aren't available.
#
# @example
#   include Manifold::Views::I18nHelpers
#
#   # Access translations
#   i18n[:page][:welcome_message]
#
module Manifold
  module Views
    module I18nHelpers
      attr_reader :i18n_enabled

      # Retrieves localized content for the view, implementing fallback behavior
      # when translations aren't available for the requested locale.
      #
      # @note PRODUCTION VS TESTING IMPACT:
      #   This implementation memoizes based on the instance variable being defined,
      #   without considering locale changes. In production, views are instantiated
      #   per-request, so locale remains consistent. In testing, reusing the same view
      #   instance with different locales will return cached data from the original locale.
      #
      #   The method correctly implements fallback to default locale and safe access
      #   patterns, but doesn't handle locale switching within the same instance.
      #
      # @return [Hash] Localized content with keys:
      #   - :locale [String] The current locale code
      #   - :default [String] The default locale code
      #   - :page [Hash] Page-specific translations
      #   - :COMMON [Hash] Shared translations across pages
      def i18n
         # Return empty hash if locales not available yet
         locales = OT.conf['locales']
         return {} unless locales

         locale        = self.locale
         @i18n_cache ||= {}
         return @i18n_cache[locale] if @i18n_cache.key?(locale)

         default-locale = OT.conf['default_locale']
         supported_locales = OT.conf['supported_locales']
         pagename = self.class.pagename
         messages = locales&.dig(locale) || {}

         # Fall back to default locale if translations not available
         if messages.empty?
           OT.le "[#{pagename}.i18n] #{locale} not found in #{locales.keys} (#{supported_locales})"
           messages = locales&.dig(default_locale) || {}
         end

         # Safe access to nested hash structure
         web_messages    = messages.fetch(:web, {})
         common_messages = web_messages.fetch(:COMMON, {})
         page_messages   = web_messages.fetch(pagename, {})

         result = {
           locale: locale,
           default: OT.conf[:default_locale],
           page: page_messages,
           COMMON: common_messages,
         }

         @i18n_cache[locale] = result
      end
    end
  end
end
