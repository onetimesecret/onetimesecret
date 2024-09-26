

require_relative 'base'
require_relative '../../app_settings'
require_relative '../../../logic/secrets'

class Onetime::App::APIV2
  class Secrets
    include Onetime::App::AppSettings
    include Onetime::App::APIV2::Base

    @check_utf8 = true
    @check_uri_encoding = true

    def get_metadata
      retrieve_records(OT::Logic::Secrets::ShowMetadata)
    end

  end
end
