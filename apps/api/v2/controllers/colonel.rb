# apps/api/v2/controllers/colonel.rb

require_relative 'base'
require_relative '../logic/colonel'

module V2
  module Controllers
    class Colonel
      include V2::Controllers::Base

      @check_utf8 = true
      @check_uri_encoding = true

      def get_info
        retrieve_records(V2::Logic::Colonel::GetColonelInfo, auth_type: :colonels)
      end

      def get_config
        retrieve_records(V2::Logic::Colonel::GetColonelSettings, auth_type: :colonels)
      end

      def update_config
        process_action(V2::Logic::Colonel::UpdateColonelSettings,
          "Config updated successfully.",
          "Config could not be updated.",
          auth_type: :colonels,
        )
      end
    end
  end
end
