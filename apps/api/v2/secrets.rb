

require_relative 'base'
require_relative '../../app_settings'
require_relative '../../../logic/secrets'

class Onetime::App::APIV2
  class Secrets
    include Onetime::App::AppSettings
    include Onetime::App::APIV2::Base

    @check_utf8 = true
    @check_uri_encoding = true

    def conceal_secret
      process_action(
        OT::Logic::Secrets::ConcealSecret,
        "Secret concealed successfully.",
        "Secret could not be concealed.",
        allow_anonymous: true,
      )
    end

    def generate_secret
      process_action(
        OT::Logic::Secrets::GenerateSecret,
        "Secret generate successfully.",
        "Secret could not be generated.",
        allow_anonymous: true,
      )
    end

    def burn_secret
      process_action(
        OT::Logic::Secrets::BurnSecret,
        "Secret burned successfully.",
        "Secret could not be burned.",
        allow_anonymous: true,
      )
    end

    def get_metadata
      retrieve_records(OT::Logic::Secrets::ShowMetadata, allow_anonymous: true)
    end

    def get_secret
      retrieve_records(OT::Logic::Secrets::ShowSecret, allow_anonymous: true)
    end

    def reveal_secret
      retrieve_records(OT::Logic::Secrets::RevealSecret, allow_anonymous: true)
    end

    def list_metadata
      retrieve_records(OT::Logic::Secrets::ShowMetadataList)
    end

  end
end
