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
        OT.auth_logger.info '[MFA Login] OTP authentication successful',
          account_id: account_id,
          email: account[:email]
        # Rodauth handles session management automatically
      end

      # ========================================================================
      # HOOK: After OTP Disable
      # ========================================================================
      auth.after_otp_disable do
        OT.auth_logger.info '[MFA] OTP disabled',
          account_id: account_id,
          email: account[:email]
        # Rodauth handles session cleanup automatically
      end
    end
  end
end
