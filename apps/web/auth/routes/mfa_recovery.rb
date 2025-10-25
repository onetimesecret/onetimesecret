# apps/web/auth/routes/mfa_recovery.rb

module Auth
  module Routes
    # MFA Recovery Routes
    #
    # Provides a recovery mechanism for users stuck in MFA verification.
    # Follows Rodauth's design by delegating to the email_auth feature.
    #
    # ## Rodauth-Aligned Design
    #
    # This implementation works WITH Rodauth instead of around it:
    # 1. Sets mfa_recovery_mode flag in session
    # 2. Returns email auth endpoint for frontend to call
    # 3. Frontend POSTs to Rodauth's /auth/email-login-request
    # 4. Rodauth handles token generation, storage, and email sending
    # 5. User clicks link → after_login hook disables MFA
    #
    # This avoids manual database manipulation or calling private methods.
    #
    # ## Flow Diagram
    #
    # ```
    # User clicks "Can't access authenticator?"
    #          ↓
    # POST /auth/mfa-recovery-request (sets recovery flag)
    #          ↓
    # POST /auth/email-login-request (Rodauth sends magic link)
    #          ↓
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
    # ## Key Architectural Points
    #
    # 1. **Rodauth Integration**: Uses Rodauth's email_auth feature natively
    # 2. **Two-Step Process**: Backend sets flag, frontend calls Rodauth
    # 3. **Hook-Based Logic**: after_login hook handles recovery detection
    # 4. **Multi-App Aware**: Uses Auth::Application.uri_prefix for routing
    #
    # ## Security
    #
    # - Recovery requires email access (same security as password reset)
    # - Uses Rodauth's cryptographic token generation
    # - Single-use, time-limited tokens (15 min default)
    # - All recovery attempts logged via SemanticLogger
    #
    # @see docs/authentication/magic-link-mfa-flow.md for full documentation
    module MfaRecovery
      def handle_mfa_recovery_routes(r)
        # MFA Recovery Initiation
        #
        # Sets recovery mode and returns email auth route.
        # Frontend will then use Rodauth's email-auth-request endpoint.
        r.post 'mfa-recovery-request' do
          unless session[:awaiting_mfa]
            response.status = 400
            next { error: 'MFA recovery not applicable' }
          end

          account_id = session['account_id']
          email = session['email']

          unless account_id && email
            response.status = 400
            next { error: 'Session data incomplete' }
          end

          SemanticLogger['Auth'].warn 'MFA recovery requested',
            account_id: account_id,
            email: OT::Utils.obscure_email(email)

          # Set flag for after_login hook to detect
          session[:mfa_recovery_mode] = true

          # Build the full email auth route
          # Use Auth::Application.uri_prefix since rodauth.prefix is empty
          # (Rodauth doesn't know about the /auth mount point)
          email_auth_route = "#{Auth::Application.uri_prefix}/#{rodauth.email_auth_request_route}"

          response.status = 200
          {
            success: 'MFA recovery initiated',
            email_auth_route: email_auth_route,
            email: email
          }
        rescue StandardError => ex
          SemanticLogger['Auth'].error 'MFA recovery failed',
            exception: ex
          session.delete(:mfa_recovery_mode)
          response.status = 500
          { error: 'Failed to initiate recovery' }
        end
      end
    end
  end
end
