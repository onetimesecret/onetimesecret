# apps/web/auth/config/features/account_management.rb

module Auth::Config::Features
  module AccountManagement
    def self.configure(auth)

      # Only configure verify_account if the feature is enabled (disabled in test)
      unless ENV['RACK_ENV'] == 'test'
        # Password is set during account creation, not during verification
        # This prevents verify_account from requiring password fields
        auth.verify_account_set_password? false
      end

      # Have successful login redirect back to originally requested page
      # @see login_return.rdoc
      auth.login_return_to_requested_location? true

      # Password requirements
      auth.password_minimum_length 8

      # Disable password confirmation field requirement
      # UI sends single password field, not password + confirmation
      auth.require_password_confirmation? false

      # Custom error messages
      # Override Rodauth's default generic error message
      # In JSON mode, this becomes the "error" field in the response
      # Field-specific errors are still returned in "field-error" array
      auth.create_account_error_flash 'Unable to create account'

    end

  end
end
