# apps/api/v2/controllers/account.rb

require_relative 'base'
require_relative 'settings'
require_relative '../logic/account'

module V2
  module Controllers
    class Account
      include V2::ControllerSettings
      include V2::ControllerBase

      @check_utf8 = true
      @check_uri_encoding = true

      def get_account
        retrieve_records(V2::Logic::Account::GetAccount)
      end

      def generate_apitoken
        process_action(
          V2::Logic::Account::GenerateAPIToken,
          "API Key generated successfully.",
          "API Key could not be generated.",
        )
      end

      def change_account_password
        process_action(
          V2::Logic::Account::UpdatePassword,
          "Password changed successfully.",
          "Password could not be changed.",
        )
      end

      def update_locale
        process_action(
          V2::Logic::Account::UpdateLocale,
          "Locale updated successfully.",
          "Locale could not be updated.",
        )
      end

      def destroy_account
        process_action(
          V2::Logic::Account::DestroyAccount,
          "Account destroyed successfully.",
          "Account could not be destroyed.",
        )
      end

    end
  end
end
