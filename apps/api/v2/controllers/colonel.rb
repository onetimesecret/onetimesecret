# apps/api/v2/controllers/colonel.rb

require_relative 'base'
require_relative 'settings'

module V2
  module Controllers
    class Colonel
      include V2::ControllerSettings
      include V2::ControllerBase

      @check_utf8 = true
      @check_uri_encoding = true

      def get_info
        retrieve_records(V2::Logic::Colonel::GetColonelInfo, auth_type: :colonels)
      end

      def get_config
        retrieve_records(V2::Logic::Colonel::GetColonelConfig, auth_type: :colonels)
      end

    end
  end
end
