# apps/web/core/views/helpers/i18n.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'

# I18nHelpers provides localization functionality for view templates.
#
# This module implements a caching mechanism for translations with
# fallback behavior when requested locales aren't available.
#
# @example
#   include Core::Views::I18nHelpers
#
#   # Access translations
#   i18n[:page][:welcome_message]
#
module Core
  module Views
    module I18nHelpers
      include Onetime::LoggerMethods

      attr_reader :i18n_enabled

      # Retrieves localized content for the view using ruby-i18n gem,
      # implementing fallback behavior when translations aren't available
      # for the requested locale.
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
        locale        = self.locale
        @i18n_cache ||= {}

        return @i18n_cache[locale] if @i18n_cache.key?(locale)

        # Set the I18n locale
        I18n.locale = locale.to_sym

        pagename = self.class.pagename

        # Get translations using I18n.t with fallback support
        web_messages = I18n.t('web', locale: locale, default: {})

        # Fall back to default locale if translations not available
        if web_messages.empty?
          app_logger.warn "Locale not found, falling back to default", {
            requested_locale: locale,
            available_locales: I18n.available_locales,
            supported_locales: OT.supported_locales,
            page: pagename
          }
          I18n.locale = OT.default_locale.to_sym
          web_messages = I18n.t('web', default: {})
        end

        # Safe access to nested hash structure
        common_messages = web_messages.fetch(:COMMON, {})
        page_messages   = web_messages.fetch(pagename, {})

        result = {
          locale: locale,
          default: OT.default_locale,
          page: page_messages,
          COMMON: common_messages,
        }

        @i18n_cache[locale] = result
      end
    end
  end
end
