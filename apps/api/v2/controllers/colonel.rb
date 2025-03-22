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

      def get_index
        retrieve_records(V2::Logic::Colonel::GetColonel, auth_type: :colonels)
      end

    end
  end
end
