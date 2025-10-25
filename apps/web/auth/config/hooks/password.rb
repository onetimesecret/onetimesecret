# apps/web/auth/config/hooks/password.rb

#
# This file defines the Rodauth hooks related to user authentication events,
# such as password changes and resets.
#

module Auth::Config::Hooks
  module Password
    def self.configure(auth)
      #
      # Hook: After Password Reset Request
      #
      # This hook is triggered after a user requests a password reset.
      #
      auth.after_reset_password_request do
        OT.info "[auth] Password reset requested for: #{account[:email]}"
      end

      #
      # Hook: After Password Reset
      #
      # This hook is triggered after a user successfully resets their password.
      #
      auth.after_reset_password do
        OT.info "[auth] Password reset for: #{account[:email]}"
      end

      #
      # Hook: After Password Change
      #
      # This hook is triggered after a user changes their password. It updates
      # metadata in the associated Onetime::Customer record.
      #
      auth.after_change_password do
        OT.info "[auth] Password changed for: #{account[:email]}"

        # Rodauth is the source of truth for password management. Here, we just
        # sync metadata to the customer record.
        Onetime::ErrorHandler.safe_execute('update_password_metadata', email: account[:email]) do
          Handlers.update_password_metadata(account)
        end
      end

    end
  end
end
