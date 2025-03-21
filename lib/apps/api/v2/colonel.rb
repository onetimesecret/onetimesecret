
require_relative 'base'
require_relative '../../app_settings'

class Onetime::App::APIV2
  class Colonel
    include Onetime::App::AppSettings
    include Onetime::App::APIV2::Base

    @check_utf8 = true
    @check_uri_encoding = true

    def get_index
      retrieve_records(OT::Logic::Colonel::GetColonel, auth_type: :colonels)
    end

  end
end
