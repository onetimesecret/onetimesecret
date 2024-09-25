
require_relative 'base'
require_relative '../../app_settings'
require_relative '../../../logic/account'

class Onetime::App::APIV2
  class Account
    include Onetime::App::AppSettings
    include Onetime::App::APIV2::Base

    @check_utf8 = true
    @check_uri_encoding = true

    # Endpoints for interactive UI (v2)
    #
    # The response objects are minimal, and are intended to be used
    # by the client to determine the next step in the UI flow. The
    # client should not rely on the response object for any data
    # other than the success flag, error messages.
    #
    # This is an intentional limitation to keep the API simple and
    # while we transition to a V2 API that will be more feature-rich.
    #

    def get_account
      retrieve_records(OT::Logic::Account::GetAccount)
    end

    def generate_apitoken
      process_action(
        OT::Logic::Account::GenerateAPIToken,
        "API Key generated successfully.",
        "API Key could not be generated."
      )
    end

    def change_account_password
      process_action(
        OT::Logic::Account::UpdateAccount,
        "Password changed successfully.",
        "Password could not be changed."
      )
    end

    def destroy_account
      process_action(
        OT::Logic::Account::DestroyAccount,
        "Account destroyed successfully.",
        "Account could not be destroyed."
      )
    end

  end
end
