# apps/api/v3/logic/meta.rb
#
# frozen_string_literal: true

# V3 Meta Logic
#
# Delegates to V2 meta logic. No changes needed as meta endpoints
# already return native types (not model serialization).

require_relative '../../v2/logic/meta'

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

      # Delegate to V2 implementations (already return native types)
      def self.get_supported_locales(req, res)
        V2::Logic::Meta.get_supported_locales(req, res)
      end

      def self.system_status(req, res)
        V2::Logic::Meta.system_status(req, res)
      end

      def self.system_version(req, res)
        V2::Logic::Meta.system_version(req, res)
      end
    end
  end
end
