# apps/api/v3/logic/meta.rb
#
# frozen_string_literal: true

# V3 Meta Logic
#
# Native V3 implementations following pure REST conventions.
# HTTP status codes indicate success/error — no `success` field in responses.

module V3
  module Logic
    # @api System metadata endpoints for health checks, version info, and
    #   supported locale listings. These endpoints do not require
    #   authentication.
    module Meta
      SCHEMAS = {
        system_status: { response: 'systemStatus' },
        system_version: { response: 'systemVersion' },
        get_supported_locales: { response: 'supportedLocales' },
      }.freeze

      # Get Supported Locales
      #
      # @api Returns the list of supported locales and the default locale
      #   for the application.
      def self.get_supported_locales(_req, _res)
        supported_locales = OT.supported_locales.map(&:to_s)
        default_locale    = OT.default_locale
        {
          locales: supported_locales,
          default_locale: default_locale,
          locale: default_locale,
        }
      end

      # System Status
      #
      # @api Returns the current operational status of the system.
      def self.system_status(_req, _res)
        {
          status: :nominal,
          locale: OT.default_locale,
        }
      end

      # System Version
      #
      # @api Returns the current application version as an array of
      #   version components.
      def self.system_version(_req, _res)
        {
          version: OT::VERSION.to_a,
          locale: OT.default_locale,
        }
      end
    end
  end
end
