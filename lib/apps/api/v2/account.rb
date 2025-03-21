
require_relative 'base'
require_relative '../../app_settings'
require_relative '../../../logic/account'

module V2::API
  class Account
    include Onetime::App::AppSettings
    include Onetime::App::APIV2::Base

    @check_utf8 = true
    @check_uri_encoding = true

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
        OT::Logic::Account::UpdatePassword,
        "Password changed successfully.",
        "Password could not be changed."
      )
    end

    def update_locale
      process_action(
        OT::Logic::Account::UpdateLocale,
        "Locale updated successfully.",
        "Locale could not be updated."
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
