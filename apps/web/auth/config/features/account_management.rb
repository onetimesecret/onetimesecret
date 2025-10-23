# apps/web/auth/config/features/account_management.rb

module Auth
  module Config
    module Features
      module AccountManagement
        def self.configure(auth)

          # Table column configurations
          # All Rodauth tables use account_id as FK, not id
          auth.verify_account_table :account_verification_keys
          auth.verify_account_id_column :account_id
          auth.reset_password_table :account_password_reset_keys
          auth.reset_password_id_column :account_id

          # Password requirements
          auth.password_minimum_length 8

          # Disable password confirmation field requirement
          # UI sends single password field, not password + confirmation
          auth.require_password_confirmation? false

          # Password is set during account creation, not during verification
          # This prevents verify_account from requiring password fields
          # Only configure if verify_account feature is enabled
          auth.verify_account_set_password? false unless ENV['RACK_ENV'] == 'test'

          # Custom error messages
          # Override Rodauth's default generic error message
          # In JSON mode, this becomes the "error" field in the response
          # Field-specific errors are still returned in "field-error" array
          auth.create_account_error_flash 'Unable to create account'

        end
      end
    end
  end
end
