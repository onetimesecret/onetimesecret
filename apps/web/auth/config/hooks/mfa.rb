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
      # HOOK: Before OTP Setup Route
      # ========================================================================
      #
      # This hook ensures the session is valid before MFA setup begins.
      # The issue: Rodauth's otp_setup route calls require_account, which calls
      # require_account_session. If account_from_session fails to load the account
      # from the database, it clears the session and redirects to login.
      #
      # This hook validates and logs session state to prevent unexpected logouts.
      #
      auth.before_otp_setup_route do
        # Log session state for debugging
        Auth::Logging.log_auth_event(
          :mfa_setup_route_start,
          level: :debug,
          account_id: session_value,
          session_keys: session.keys,
          has_account_id: !session_value.nil?,
          request_method: request.request_method,
          has_otp_code: !request.params['otp_code'].to_s.empty?,
        )

        # Critical: Ensure the account_id is in the session
        # The issue is that between password verification and OTP setup,
        # the session might not have account_id properly set
        if session_value
          # Try to load account to ensure it's accessible
          begin
            acct = _account_from_session
            unless acct
              Auth::Logging.log_auth_event(
                :mfa_setup_account_not_found,
                level: :error,
                account_id: session_value,
                message: "Session has account_id but account not found in database",
              )
            end
          rescue => e
            Auth::Logging.log_auth_event(
              :mfa_setup_account_lookup_error,
              level: :error,
              account_id: session_value,
              error: e.message,
              backtrace: e.backtrace.first(3),
            )
          end
        else
          Auth::Logging.log_auth_event(
            :mfa_setup_missing_session,
            level: :error,
            session_keys: session.keys,
            message: "No account_id in session during MFA setup",
          )
        end
      end

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
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :mfa_authentication_success,
          level: :info,
          account_id: account_id,
          email: account[:email],
          correlation_id: correlation_id,
        )

        # Measure and log session sync duration
        Auth::Logging.measure(:mfa_session_sync, account_id: account_id, correlation_id: correlation_id) do
          # Rodauth handles session management automatically, but we sync session data
          Onetime::ErrorHandler.safe_execute('sync_session_after_mfa',
            account_id: account_id,
            email: account[:email],
          ) do
            Auth::Operations::SyncSession.call(
              account: account,
              account_id: account_id,
              session: session,
              request: request,
              correlation_id: correlation_id,
            )
          end
        end

        # Log metric for MFA completion
        Auth::Logging.log_metric(
          :mfa_authentication_complete,
          value: 1,
          unit: :count,
          account_id: account_id,
          correlation_id: correlation_id,
        )

        # Clear awaiting_mfa flag
        session[:awaiting_mfa] = false

        # Clean up correlation ID after successful completion
        session.delete(:auth_correlation_id)
      end

      # ========================================================================
      # HOOK: After OTP Disable
      # ========================================================================
      auth.after_otp_disable do
        Auth::Logging.log_auth_event(
          :mfa_disabled,
          level: :info,
          account_id: account_id,
          email: account[:email],
        )

        # Log metric for MFA disable
        Auth::Logging.log_metric(
          :mfa_disabled,
          value: 1,
          unit: :count,
          account_id: account_id,
        )
        # Rodauth handles session cleanup automatically
      end

      # ========================================================================
      # HOOK: After OTP Setup
      # ========================================================================
      auth.after_otp_setup do
        Auth::Logging.log_auth_event(
          :mfa_setup_success,
          level: :info,
          account_id: account_id,
          email: account[:email],
        )

        # Include recovery codes in JSON response for user to save
        # Recovery codes are auto-generated by auto_add_recovery_codes? true
        if json_request? && respond_to?(:recovery_codes)
          json_response[:recovery_codes] = recovery_codes
        end

        # Log metric for MFA setup
        Auth::Logging.log_metric(
          :mfa_setup_success,
          value: 1,
          unit: :count,
          account_id: account_id,
        )
      end

      # ========================================================================
      # HOOK: After OTP Authentication Failure
      # ========================================================================
      auth.after_otp_authentication_failure do
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :mfa_authentication_failure,
          level: :warn,
          account_id: account_id,
          email: account[:email],
          correlation_id: correlation_id,
        )

        # Log metric for MFA failure
        Auth::Logging.log_metric(
          :mfa_authentication_failure,
          value: 1,
          unit: :count,
          account_id: account_id,
          correlation_id: correlation_id,
        )
      end
    end
  end
end
