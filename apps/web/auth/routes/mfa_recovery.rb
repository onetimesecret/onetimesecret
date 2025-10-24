# apps/web/auth/routes/mfa_recovery.rb

module Auth
  module Routes
    # MFA Recovery Routes
    #
    # Handles the recovery flow for users who cannot complete MFA verification
    # due to lost authenticator access or invalidated OTP keys.
    #
    # ## Problem Scenario
    #
    # Users can become stuck in MFA verification when:
    # - OTP keys are invalidated (e.g., config changes to otp_keys_use_hmac)
    # - Authenticator device lost or broken
    # - Recovery codes unavailable or lost
    #
    # The user is in `awaiting_mfa` state but cannot provide valid credentials,
    # creating an infinite loop with no escape route.
    #
    # ## Solution
    #
    # This recovery mechanism leverages the existing email_auth (magic link)
    # infrastructure to provide a secure escape path:
    #
    # 1. User requests recovery while stuck on /mfa-verify
    # 2. System sends magic link with special recovery flag
    # 3. Clicking link authenticates AND disables MFA automatically
    # 4. User can re-enable MFA from account settings after login
    #
    # #### Flow Diagram
    #
    # ```
    # User clicks magic link
    #          ↓
    # Email auth validates token
    #          ↓
    # Rodauth triggers LOGIN
    #          ↓
    # after_login hook fires
    #          ↓
    # Check: session[:mfa_recovery_mode]?
    #     ├── YES → Disable MFA → Continue login (skip MFA check)
    #     └── NO  → Check uses_two_factor_authentication?
    #                 ├── YES → Set awaiting_mfa, defer session sync
    #                 └── NO  → Complete session sync normally
    # ```
    #
    # The key insight is that email_auth completes by triggering the standard
    # login flow, so the `after_login` hook in login.rb naturally intercepts
    # the recovery flow before the normal MFA check occurs.
    #
    # ## Security
    #
    # - Recovery requires email access (same security level as password reset)
    # - Uses cryptographically secure, single-use, time-limited tokens (15min)
    # - Only works when user is in partial auth state (email/password verified)
    # - All recovery attempts logged via SemanticLogger
    # - MFA can be immediately re-enabled from account settings
    module MfaRecovery
      def handle_mfa_recovery_routes(r)
        # MFA Recovery Request Endpoint
        #
        # Sends a recovery email to users stuck in MFA verification state.
        # Uses email_auth infrastructure to send a magic link that will
        # disable MFA and complete authentication.
        #
        # Request: POST /auth/mfa-recovery-request
        # Auth: Requires awaiting_mfa session state
        # Response: { success: "message" } or { error: "message" }
        r.post 'mfa-recovery-request' do
          # Verify user is actually in MFA waiting state
          unless session[:awaiting_mfa]
            response.status = 400
            next { error: 'MFA recovery not applicable' }
          end

          # Verify account exists and has email
          account_id = session['account_id']
          email = session['email']

          unless account_id && email
            response.status = 400
            next { error: 'Session data incomplete' }
          end

          SemanticLogger['Auth'].warn 'MFA recovery requested',
            account_id: account_id,
            email: OT::Utils.obscure_email(email)

          # Set recovery mode flag
          session[:mfa_recovery_mode] = true

          # Trigger email auth request flow
          # This will send a magic link to the user's email
          Onetime::ErrorHandler.safe_execute('mfa_recovery_send_email',
            account_id: account_id,
            email: email
          ) do
            # Use Rodauth's email_auth methods
            # _email_auth_key_insert generates and stores the token
            rodauth._email_auth_key_insert(account_id)

            # send_email_auth_email sends the email with the magic link
            rodauth.send_email_auth_email

            SemanticLogger['Auth'].info 'MFA recovery email sent',
              account_id: account_id,
              email: OT::Utils.obscure_email(email)
          end

          # Return success response
          response.status = 200
          {
            success: 'Recovery email sent. Please check your email for a login link.'
          }
        rescue StandardError => ex
          SemanticLogger['Auth'].error 'MFA recovery request failed',
            account_id: account_id,
            email: OT::Utils.obscure_email(email),
            exception: ex

          response.status = 500
          { error: 'Failed to send recovery email' }
        end
      end
    end
  end
end
