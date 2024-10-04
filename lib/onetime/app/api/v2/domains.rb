

require_relative 'base'
require_relative '../../app_settings'
require_relative '../../../logic/domains'

class Onetime::App::APIV2
  class Domains
    include Onetime::App::AppSettings
    include Onetime::App::APIV2::Base

    @check_utf8 = true
    @check_uri_encoding = true

    def add_domain
      OT.ld "[API::Domains] add_domain #{req.params}"
      process_action(
        OT::Logic::Domains::AddDomain,
        "Domain added successfully.",
        "Domain could not be added."
      )
    end

    def verify_domain
      process_action(
        OT::Logic::Domains::VerifyDomain,
        "Domain verified.",
        "Domain could not be verified."
      )
    end

    def remove_domain
      process_action(
        OT::Logic::Domains::RemoveDomain,
        "Domain removed successfully.",
        "Domain could not be removed."
      )
    end

    def get_domain
      retrieve_records(OT::Logic::Domains::GetDomain)
    end

    def list_domains
      # Probably we only need logic for requests with side effects (POST
      # etc). We can handle the access controls and params stuff here or
      # in a lighter way so it doesn't feel like so much machinery just
      # to return a single record (get_domain et al).
      retrieve_records(OT::Logic::Domains::ListDomains)
    end

  end
end
