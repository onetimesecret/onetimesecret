# apps/api/v2/colonel.rb

require_relative 'base'
require_relative '../../app_settings'

class V2
  class Colonel
    include Onetime::App::AppSettings
    include V2::Base

    @check_utf8 = true
    @check_uri_encoding = true

    def get_index
      retrieve_records(V2::Logic::Colonel::GetColonel, auth_type: :colonels)
    end

  end
end
