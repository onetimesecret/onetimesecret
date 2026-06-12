# apps/web/auth/config/hooks/mfa.rb
#
# frozen_string_literal: true

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
    def self.configure(auth) # rubocop:disable Metrics/PerceivedComplexity
      # ========================================================================
      # HOOK: Before OTP Setup Route
      # ========================================================================
      #
      # This hook logs MFA setup attempts and validates session state.
      #
      # Logging strategy:
      # - GET requests: Log route access for debugging
      # - POST requests: Log setup attempts (with/without OTP code)
      #
      # This provides visibility into:
      # - Initial setup page loads (GET)
      # - Secret generation attempts (POST without OTP code)
      # - Verification attempts (POST with OTP code)
      #
      auth.before_otp_setup_route do
        # ----------------------------------------------------------------
        # Emit Rodauth's authoritative TOTP provisioning URI (issue #3431)
        # ----------------------------------------------------------------
        #
        # By the time this hook body runs, Rodauth's json feature has already
        # executed (via super) its own before_otp_setup_route, which — in the
        # HMAC JSON flow — generates the setup secret and populates the
        # response with:
        #   - otp_setup_param     => otp_user_key (the HMAC'd key the
        #                            authenticator must actually use)
        #   - otp_setup_raw_param => the raw key, used ONLY for the setup
        #                            handshake (NOT a valid TOTP secret)
        #
        # The SPA historically reconstructed the otpauth:// URI itself and, on
        # the HMAC path, encoded the raw key — so scanned codes never matched
        # what the server validates (otp built from otp_user_key), while the
        # manually-displayed otp_setup key worked. We instead emit Rodauth's
        # own otp_provisioning_uri (built from otp_user_key, with the correct
        # issuer/digits/period) as the single source of truth, so the frontend
        # can render the QR directly without guessing the secret or params.
        #
        # Rebuild the tmp OTP key from the raw secret we just handed the client
        # so otp_provisioning_uri reflects exactly that secret, independent of
        # any later key regeneration in the route body.
        if otp_keys_use_hmac? && (raw_secret = json_response[otp_setup_raw_param])
          otp_tmp_key(raw_secret)
          json_response[:provisioning_uri] = otp_provisioning_uri
        end

        is_post      = request.post?
        has_otp_code = !param_or_nil(otp_auth_param).to_s.empty?
        has_password = !param_or_nil(password_param).to_s.empty?

        # Log setup attempts (POST requests)
        if is_post
          # Determine attempt type based on parameters
          attempt_type = if has_otp_code
                          :verification  # Step 2: Verifying OTP code
                        else
                          :initiation    # Step 1: Generating secret
                        end

          Auth::Logging.log_auth_event(
            :mfa_setup_attempt,
            level: :info,
            log_metric: true,
            account_id: session_value,
            email: account&.[](:email),
            attempt_type: attempt_type,
            has_otp_code: has_otp_code,
            has_password: has_password,
            ip: request.ip,
            request_method: request.request_method,
          )
        else
          # GET request - just accessing setup page
          Auth::Logging.log_auth_event(
            :mfa_setup_route_start,
            level: :debug,
            account_id: session_value,
            ip: request.ip,
            request_method: request.request_method,
          )
        end

        # Session validation (debug logging)
        if session_value
          begin
            acct = _account_from_session
            unless acct
              Auth::Logging.log_auth_event(
                :mfa_setup_account_not_found,
                level: :error,
                account_id: session_value,
                message: 'Session has account_id but account not found in database',
              )
            end
          rescue StandardError => ex
            Auth::Logging.log_auth_event(
              :mfa_setup_account_lookup_error,
              level: :error,
              account_id: session_value,
              error: ex.message,
            )
          end
        else
          Auth::Logging.log_auth_event(
            :mfa_setup_missing_session,
            level: :error,
            message: 'No account_id in session during MFA setup',
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

        # Calculate verification duration if we have start time
        duration_ms = if session[:mfa_verification_start]
                       start = session.delete(:mfa_verification_start)
                       ((Onetime.now_in_μs - start) / 1000.0).round(2)
                     end

        Auth::Logging.log_auth_event(
          :mfa_verification_success,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
          duration_ms: duration_ms,
          correlation_id: correlation_id,
        )

        # Measure and log session sync duration
        Auth::Logging.measure(:mfa_session_sync, account_id: account_id, correlation_id: correlation_id) do
          # Rodauth handles session management automatically, but we sync session data
          Onetime::ErrorHandler.safe_execute(
            'sync_session_after_mfa',
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

        # Billing redirect: add plan selection to JSON response (issue #3275).
        # Billing.configure defines add_billing_redirect_to_response via auth_class_eval,
        # so the method is only available when billing is enabled. Check respond_to?
        # to avoid NoMethodError when billing is disabled (self-hosted).
        if json_request? && respond_to?(:add_billing_redirect_to_response)
          add_billing_redirect_to_response
        end
      end

      # ========================================================================
      # HOOK: After OTP Disable
      # ========================================================================
      auth.after_otp_disable do
        Auth::Logging.log_auth_event(
          :mfa_disabled,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
        )
        # Rodauth handles session cleanup automatically
      end

      # ========================================================================
      # HOOK: After OTP Setup
      # ========================================================================
      #
      # This hook runs after successful MFA setup completion.
      # It fires inside the database transaction, ensuring atomicity.
      #
      # At this point:
      # - OTP secret has been validated and stored
      # - Password has been verified
      # - OTP code has been confirmed
      # - Recovery codes have been generated (if auto_add_recovery_codes? true)
      #
      auth.after_otp_setup do
        recovery_codes_count = respond_to?(:recovery_codes) ? recovery_codes.length : 0

        Auth::Logging.log_auth_event(
          :mfa_setup_success,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          recovery_codes_generated: recovery_codes_count,
          hmac_enabled: otp_keys_use_hmac?,
        )

        # Include recovery codes in JSON response for user to save
        # Recovery codes are auto-generated by auto_add_recovery_codes? true
        if json_request? && respond_to?(:recovery_codes)
          json_response[:recovery_codes] = recovery_codes
        end
      end

      # ========================================================================
      # HOOK: Before OTP Auth Route
      # ========================================================================
      #
      # This hook logs MFA verification attempts before processing.
      # Provides visibility into:
      # - GET requests: Accessing verification page
      # - POST requests: Submitting OTP code for verification
      #
      auth.before_otp_auth_route do
        is_post        = request.post?
        has_otp_code   = !param_or_nil(otp_auth_param).to_s.empty?
        correlation_id = session[:auth_correlation_id]

        if is_post
          # Log verification attempt with timing
          session[:mfa_verification_start] = Onetime.now_in_μs

          Auth::Logging.log_auth_event(
            :mfa_verification_attempt,
            level: :info,
            log_metric: true,
            account_id: session_value,
            email: account&.[](:email),
            has_otp_code: has_otp_code,
            ip: request.ip,
            correlation_id: correlation_id,
          )
        else
          # GET request - accessing verification page
          Auth::Logging.log_auth_event(
            :mfa_verification_route_start,
            level: :debug,
            account_id: session_value,
            ip: request.ip,
            correlation_id: correlation_id,
          )
        end
      end

      # ========================================================================
      # HOOK: Before OTP Authentication
      # ========================================================================
      #
      # This hook fires just before validating the OTP code.
      # Use for last-minute checks or enriched logging.
      #
      auth.before_otp_authentication do
        correlation_id = session[:auth_correlation_id]

        Auth::Logging.log_auth_event(
          :mfa_verification_validating,
          level: :debug,
          account_id: account_id,
          correlation_id: correlation_id,
        )
      end

      # ========================================================================
      # HOOK: After OTP Authentication Failure
      # ========================================================================
      #
      # This hook logs failed MFA verification attempts.
      # Captures timing, IP, and increments failure metrics.
      #
      auth.after_otp_authentication_failure do
        correlation_id = session[:auth_correlation_id]

        # Calculate verification duration if we have start time
        duration_ms = if session[:mfa_verification_start]
                       start = session.delete(:mfa_verification_start)
                       ((Onetime.now_in_μs - start) / 1000.0).round(2)
                     end

        Auth::Logging.log_auth_event(
          :mfa_verification_failure,
          level: :warn,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
          duration_ms: duration_ms,
          correlation_id: correlation_id,
        )
      end

      # ========================================================================
      # HOOK: Before Recovery Auth
      # ========================================================================
      #
      # This hook logs recovery code authentication attempts.
      # Recovery codes are backup codes used when primary MFA is unavailable.
      #
      auth.before_recovery_auth do
        correlation_id = session[:auth_correlation_id]
        recovery_code  = param_or_nil(recovery_codes_param)

        Auth::Logging.log_auth_event(
          :mfa_recovery_code_attempt,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
          has_recovery_code: !recovery_code.to_s.empty?,
          correlation_id: correlation_id,
        )
      end

      # ========================================================================
      # HOOK: After Add Recovery Codes
      # ========================================================================
      #
      # This hook logs when recovery codes are generated/regenerated.
      # Important for security auditing.
      #
      auth.after_add_recovery_codes do
        codes_count = respond_to?(:recovery_codes) ? recovery_codes.length : 0

        Auth::Logging.log_auth_event(
          :mfa_recovery_codes_generated,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
          codes_count: codes_count,
        )
      end

      # ========================================================================
      # HOOK: Before View Recovery Codes
      # ========================================================================
      #
      # This hook logs when users access their recovery codes.
      # Important for detecting potential account compromise.
      #
      auth.before_view_recovery_codes do
        Auth::Logging.log_auth_event(
          :mfa_recovery_codes_viewed,
          level: :info,
          log_metric: true,
          account_id: account_id,
          email: account[:email],
          ip: request.ip,
        )
      end
    end
  end
end
