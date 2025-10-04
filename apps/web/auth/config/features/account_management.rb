# frozen_string_literal: true

module Auth
  module Config
    module Features
      module AccountManagement
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Account management features
            enable :create_account, :close_account, :change_password, :reset_password

            # Account verification (email confirmation) - disabled
            # require_email_confirmation_for_new_accounts true
            # verify_account_email_subject 'OneTimeSecret - Confirm Your Account'

            # Password requirements
            password_minimum_length 8
            # password_complexity_requirements_enforced true  # Feature not available in current Rodauth version
          end
        end
      end
    end
  end
end
