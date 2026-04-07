# apps/web/auth/config/features/account_management.rb
#
# frozen_string_literal: true

module Auth::Config::Features
  module AccountManagement
    def self.configure(auth)
      # Account lifecycle features
      auth.enable :create_account
      auth.enable :close_account
      auth.enable :change_password
      auth.enable :reset_password

      # Only configure verify_account if the feature is enabled
      # (disabled in test mode via YAML config: RACK_ENV != 'test')
      if Onetime.auth_config.verify_account_enabled?
        auth.enable :verify_account

        # Password is set during account creation, not during verification
        # This prevents verify_account from requiring password fields
        auth.verify_account_set_password? false

        # Suppress verification email only for valid invite signups.
        # The invite link proves email ownership, so no extra verification needed.
        # SECURITY: Token must be validated here — checking the raw param alone
        # would let an attacker add invite_token=garbage to suppress the email
        # for any signup, enabling email squatting.
        auth.send_verify_account_email do
          invite_token = request.params['invite_token'].to_s.strip
          if invite_token.empty?
            super()
          else
            invitation = Onetime::OrganizationMembership.find_by_token(invite_token)
            super() unless invitation &&
                           invitation.pending? &&
                           !invitation.expired? &&
                           OT::Utils.normalize_email(invitation.invited_email) ==
                           OT::Utils.normalize_email(param(login_param))
          end
        end
      end

      # Auto-login after invite signup (flag set in after_create_account hook)
      auth.create_account_autologin? do
        @invite_accepted == true
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
