# apps/web/auth/config/hooks/mfa.rb
#
# ==============================================================================
# USER JOURNEY: MULTI-FACTOR AUTHENTICATION (MFA) SETUP AND VERIFICATION
# ==============================================================================
#
# This file configures Rodauth hooks that intercept and customize the MFA flow
# for JSON API requests. The user's journey through MFA setup follows this path:
#
# 1. USER INITIATES MFA SETUP (before_otp_setup_route - Step 1)
#    - User requests POST /otp-setup without an OTP code
#    - Server generates a new TOTP secret (base32 encoded, 16 chars)
#    - If HMAC is enabled, server creates HMAC-secured version of secret
#    - Both secrets stored in session: :otp_setup_raw and :otp_setup_hmac
#    - Response includes:
#      * raw secret (for manual entry)
#      * provisioning URI (otpauth://totp/...)
#      * QR code SVG (visual representation)
#      * HMAC parameters (if enabled)
#    - User receives QR code and secret to configure authenticator app
#
# 2. USER SCANS QR CODE
#    - User opens authenticator app (Google Authenticator, Authy, etc.)
#    - Scans QR code or manually enters the raw secret
#    - Authenticator begins generating 6-digit codes every 30 seconds
#
# 3. USER VERIFIES SETUP (before_otp_setup_route - Step 2)
#    - User submits POST /otp-setup WITH an OTP code from authenticator
#    - Server validates HMAC parameters against session (if enabled)
#    - Server retrieves raw secret from session
#    - Rodauth validates OTP code against raw secret using ROTP library
#    - If valid, Rodauth stores HMAC secret to database
#    - Flow continues to after_otp_setup hook
#
# 4. CLEANUP (after_otp_setup)
#    - Server removes temporary session data
#    - MFA setup complete - user's account now requires 2FA for login
#
#
# ==============================================================================

module Auth::Config::Hooks
  # All Valid Hooks:
  # after_otp_authentication_failure: after OTP authentication failure.
  # after_otp_disable: after OTP authentication has been disabled.
  # after_otp_setup: after OTP authentication has been setup.
  # before_otp_auth_route: before handling an OTP authentication route.
  # before_otp_authentication: before OTP authentication.
  # before_otp_disable: before OTP authentication disabling.
  # before_otp_disable_route: before handling an OTP authentication disable route.
  # before_otp_setup: before OTP authentication setup.
  # before_otp_setup_route: before handling an OTP authentication setup route.
  #
  module MFA
    def self.configure(auth)

      # ========================================================================
      # HOOK: After Successful Two-Factor Authentication
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires after successful OTP verification during login.
      # It completes the authentication flow and syncs the session.
      #
      # NOTE: This hook is provided by two_factor_base (which is automatically
      # included when enabling the OTP feature via `depends :two_factor_base`).
      # It fires after successful two-factor authentication of any type (OTP, WebAuthn, etc).
      #
      auth.after_two_factor_authentication do
        Onetime.auth_logger.info '[MFA Login] OTP authentication successful',
          account_id: account_id,
          email: account[:email]

        if session[:awaiting_mfa]
          Onetime.auth_logger.info '[MFA Login] Completing deferred session sync'
          Onetime::ErrorHandler.safe_execute('sync_session_after_mfa',
            account_id: account_id,
            email: account[:email],
          ) do
            Auth::Operations::SyncSession.call(
              account: account,
              account_id: account_id,
              session: session,
              request: request,
            )
            session.delete(:awaiting_mfa)
          end
        end
      end
    end
  end
end
