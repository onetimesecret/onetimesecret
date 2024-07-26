

require_relative 'base'
require_relative '../../base'
require_relative '../../../logic/domains'

class Onetime::App::API
  class Domains
    include Onetime::App::AppSettings
    include Onetime::App::API::Base

    @check_utf8 = true
    @check_uri_encoding = true

    def add_domain
      OT.ld "[API::Domains] add_domain"
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

    def list_domains
      process_action(OT::Logic::Domains::ListDomains)
    end

  end
end
