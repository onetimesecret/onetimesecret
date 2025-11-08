# apps/api/v3/logic/meta.rb

# V3 Meta Logic
#
# Delegates to V2 meta logic. No changes needed as meta endpoints
# already return native types (not model serialization).

require_relative '../../v2/logic/meta'

module V3
  module Logic
    module Meta
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
