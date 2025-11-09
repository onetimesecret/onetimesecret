# apps/api/v2/logic/meta.rb
#
# frozen_string_literal: true

require_relative 'base'

module V2
  module Logic
    module Meta
      # Static methods that return system information
      def self.get_supported_locales(req, res)
        supported_locales = OT.supported_locales.map(&:to_s)
        default_locale = OT.default_locale
        {
          success: true,
          locales: supported_locales,
          default_locale: default_locale,
          locale: default_locale
        }
      end

      def self.system_status(req, res)
        {
          success: true,
          status: :nominal,
          locale: OT.default_locale
        }
      end

      def self.system_version(req, res)
        {
          success: true,
          version: OT::VERSION.to_a,
          locale: OT.default_locale
        }
      end

    end
  end
end
