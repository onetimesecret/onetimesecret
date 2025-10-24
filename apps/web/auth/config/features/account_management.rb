# apps/web/auth/config/features/account_management.rb

module Auth
  module Config
    module Features
      module AccountManagement
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Account management features
            features = [:create_account, :close_account, :change_password, :reset_password]

            # Only enable verify_account in non-test environments
            features << :verify_account unless ENV['RACK_ENV'] == 'test'

            enable *features

            # Table column configurations
            # All Rodauth tables use account_id as FK, not id
            verify_account_table :account_verification_keys
            verify_account_id_column :account_id
            reset_password_table :account_password_reset_keys
            reset_password_id_column :account_id

            # Password requirements
            password_minimum_length 8

            # Disable password confirmation field requirement
            # UI sends single password field, not password + confirmation
            require_password_confirmation? false

            # Password is set during account creation, not during verification
            # This prevents verify_account from requiring password fields
            # Only configure if verify_account feature is enabled
            verify_account_set_password? false unless ENV['RACK_ENV'] == 'test'

            # Custom error messages
            # Override Rodauth's default generic error message
            # In JSON mode, this becomes the "error" field in the response
            # Field-specific errors are still returned in "field-error" array
            create_account_error_flash 'Unable to create account'
          end
        end
      end
    end
  end
end
