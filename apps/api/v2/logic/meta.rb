# apps/api/v2/logic/meta.rb
#
# frozen_string_literal: true

require_relative 'base'

module V2
  module Logic
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
          success: true,
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
          success: true,
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
          success: true,
          version: OT::VERSION.to_a,
          locale: OT.default_locale,
        }
      end
    end
  end
end
