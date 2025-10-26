# apps/web/auth/config/hooks/mfa.rb

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
