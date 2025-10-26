# apps/web/auth/config/features/account_management.rb

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
        email = param('login') || param('email')

        # 1. Presence Check
        # Ensure an email address was actually provided.
        unless email && !email.to_s.strip.empty?
          throw_error_status(422, 'login', 'Email is required')
        end

        # 2. Email Format and Deliverability Validation (Truemail)
        # Use the Truemail gem to perform deep validation on the email address.
        begin
          validator = Truemail.validate(email)
          unless validator.result.valid?
            OT.info "[auth] Invalid email rejected: #{OT::Utils.obscure_email(email)}"
            throw_error_status(422, 'login', 'Please enter a valid email address')
          end
        rescue StandardError => ex
          SemanticLogger['Auth'].error "Email validation service failed - failing open to allow signup",
            email: OT::Utils.obscure_email(email),
            exception: ex,
            note: "Consider hard failure for higher security"
          # Fail open on validation errors, but notify for investigation.
          # For higher security, this could be changed to a hard failure.
          throw_error_status(422, 'login', 'There was a problem validating your email. Please try again.')
        end

        # 3. Security: Email Enumeration Prevention (CWE-204)
        # Check if account already exists. If it does, we handle it silently
        # to prevent attackers from discovering which emails are registered.
        existing_account = db[:accounts].where(email: email, status_id: [1, 2]).first # 1=Unverified, 2=Verified

        if existing_account
          # Account already exists - handle silently without revealing this fact
          if existing_account[:status_id] == 1 # Unverified
            # Resend verification email for unverified accounts
            OT.info "[auth] Account exists (unverified), resending verification: #{OT::Utils.obscure_email(email)}"
            # TODO: Trigger resend of verification email when email system is active
            # send_create_account_email
          else
            # Verified account - do nothing but log for security monitoring
            OT.info "[auth] Account exists (verified), silent success: #{OT::Utils.obscure_email(email)}"
          end

          # Return success without creating account
          # This prevents enumeration by always returning the same success message
          set_notice_flash 'If an account with this email exists, you will receive a verification email.'
          request.redirect create_account_redirect
        end
      end

      #
      # Hook: After Account Creation
      #
      # This hook is triggered after a new user successfully creates an account.
      # It ensures a corresponding Onetime::Customer record is created and linked.
      #
      auth.after_create_account do
        OT.info "[auth] New account created: #{account[:extid]} (ID: #{account_id})"

        Onetime::ErrorHandler.safe_execute('create_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::CreateCustomer.new(
            account_id: account_id,
            account: account,
            db: Auth::Database.connection
          ).call
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
      if ENV['RACK_ENV'] != 'test'
        auth.after_verify_account do
          OT.info "[auth] Account verified: #{account[:extid]}"

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
        OT.info "[auth] Account closed: #{account[:extid]} (ID: #{account_id})"

        Onetime::ErrorHandler.safe_execute('delete_customer', account_id: account_id, extid: account[:extid]) do
          Auth::Operations::DeleteCustomer.new(account: account).call
        end
      end

    end
  end
end
