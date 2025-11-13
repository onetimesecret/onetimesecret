# apps/web/auth/config/hooks/account.rb
#
# frozen_string_literal: true

module Auth::Config::Hooks
  module Account
    def self.configure(auth)
      #
      # Hook: Before Account Creation
      #
      # This hook is triggered before a new account is created. It performs
      # several validation checks on the provided email address.
      #
      auth.before_create_account do

      end

      auth.login_valid_email? do |email|
        validator = Truemail.validate(email)
        is_valid = super(email) && validator.result.valid?

        Auth::Logging.log_auth_event(
          :invalid_email_rejected,
          level: :info,
          email: email
        ) unless is_valid

        is_valid
      end

      #
      # Hook: After Account Creation
      #
      # This hook is triggered after a new user successfully creates an account.
      # It ensures a corresponding Onetime::Customer record is created and linked,
      # and creates a default organization and team for the new user.
      #
      auth.after_create_account do
        customer = Onetime::ErrorHandler.safe_execute('create_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::CreateCustomer.new(
            account_id: account_id,
            account: account,
            db: Auth::Database.connection
          ).call
        end

        # Create default organization and team for the new customer
        # Note: These are hidden from individual plan users in the UI
        if customer
          Onetime::ErrorHandler.safe_execute('create_default_workspace', custid: customer.custid) do
            Auth::Operations::CreateDefaultWorkspace.new(customer: customer).call
          end
        end
      end

      #
      # Hook: After Account Verification
      #
      # This hook is triggered when a user verifies their account (e.g., by
      # clicking a link in an email). It updates the verification status of
      # the associated Onetime::Customer record.
      #
      # Note: This hook is disabled in the 'test' environment to simplify
      # testing scenarios that do not require email verification flows.
      #
      unless Onetime.env?('testing')
        auth.after_verify_account do
          Auth::Logging.log_auth_event(
            :account_verified,
            level: :info,
            account_id: account_id,
            external_id: account[:external_id],
            email: account[:email]
          )

          Onetime::ErrorHandler.safe_execute('verify_customer', extid: account[:extid]) do
            Auth::Operations::VerifyCustomer.new(account: account).call
          end
        end
      end

      #
      # Hook: After Password Reset Request
      #
      # This hook is triggered after a user requests a password reset.
      #
      auth.after_reset_password_request do
        Auth::Logging.log_auth_event(
          :password_reset_requested,
          level: :info,
          account_id: account_id,
          email: account[:email]
        )
      end

      #
      # Hook: After Password Reset
      #
      # This hook is triggered after a user successfully resets their password.
      #
      auth.after_reset_password do
        Auth::Logging.log_auth_event(
          :password_reset_complete,
          level: :info,
          account_id: account_id,
          email: account[:email]
        )
      end

      #
      # Hook: After Password Change
      #
      # This hook is triggered after a user changes their password. It updates
      # metadata in the associated Onetime::Customer record.
      #
      auth.after_change_password do
        Auth::Logging.log_auth_event(
          :password_changed,
          level: :info,
          account_id: account_id,
          email: account[:email]
        )

        # Rodauth is the source of truth for password management. Here, we just
        # sync metadata to the customer record.
        Onetime::ErrorHandler.safe_execute('update_password_metadata', email: account[:email]) do
          Auth::Operations::UpdatePasswordMetadata.new(account: account).call
        end
      end

      #
      # Hook: After Account Closure
      #
      # This hook is triggered when a user closes their account. It handles the
      # cleanup of the associated Onetime::Customer record.
      #
      auth.after_close_account do
        Auth::Logging.log_auth_event(
          :account_closed,
          level: :info,
          account_id: account_id,
          external_id: account[:external_id],
          email: account[:email]
        )

        Onetime::ErrorHandler.safe_execute('delete_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::DeleteCustomer.new(account: account).call
        end
      end

    end
  end
end
