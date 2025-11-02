# apps/web/auth/routes/mfa.rb

module Auth
  module Routes
    module MFA
      def handle_mfa_routes(r)
        # ======================================================================
        # ROUTE OVERRIDE: OTP Authentication with Enhanced Error Logging
        # ======================================================================
        #
        # Override the default otp_auth route to log specific validation failures.
        # This provides visibility into why MFA verification attempts fail:
        # - Invalid OTP code (TOTP verification failure)
        # - Account locked/disabled
        # - Missing OTP secret
        #
        r.route(:otp_auth) do |r|
          require_login
          require_account_session

          if two_factor_authenticated?
            set_redirect_error_flash otp_already_authenticated_error_flash
            redirect otp_already_authenticated_redirect
          end

          unless otp_exists?
            set_redirect_error_flash otp_not_setup_error_flash
            redirect otp_not_setup_redirect
          end

          before_otp_auth_route

          r.get do
            otp_auth_view
          end

          r.post do
            correlation_id = session[:auth_correlation_id]
            otp_code = param(otp_auth_param)

            # Validation: OTP code verification
            unless otp_valid_code?(otp_code)
              Auth::Logging.log_auth_event(
                :mfa_verification_code_invalid,
                level: :warn,
                log_metric: true,
                account_id: account_id,
                email: account[:email],
                ip: request.ip,
                correlation_id: correlation_id,
                message: 'OTP code verification failed (incorrect code or timing issue)',
              )

              # Rodauth will handle recording the authentication failure
              otp_authentication_failure_response
            end

            # Code is valid - proceed with authentication
            before_otp_authentication
            transaction do
              otp_update_last_use
              two_factor_update_session('totp')
            end
            after_two_factor_authentication
            otp_authentication_response
          end
        end

        # ======================================================================
        # ROUTE OVERRIDE: OTP Setup with Enhanced Error Logging
        # ======================================================================
        #
        # Override the default otp_setup route to log specific validation failures.
        # This provides visibility into why MFA setup attempts fail:
        # - Invalid secret (HMAC validation failure)
        # - Invalid password (password mismatch)
        # - Invalid OTP code (TOTP verification failure)
        #
        # The logging happens at each throw_error_reason call, capturing the exact
        # validation step that failed.
        #
        r.route(:otp_setup) do |r|
          require_account

          if otp_exists?
            set_redirect_error_flash otp_already_setup_error_flash
            redirect otp_already_setup_redirect
          end

          before_otp_setup_route

          r.get do
            otp_setup_view
          end

          r.post do
            secret = param(otp_setup_param)

            # Validation Step 1: Secret validity check
            unless otp_valid_key?(secret)
              Auth::Logging.log_auth_event(
                :mfa_setup_failure,
                level: :warn,
                log_metric: true,
                account_id: account_id,
                email: account[:email],
                failure_reason: :invalid_secret,
                message: 'OTP secret validation failed (HMAC mismatch or invalid format)',
              )
              throw_error_reason(:invalid_otp_secret, invalid_field_error_status, otp_setup_param, otp_invalid_secret_message)
            end

            new_secret = if otp_keys_use_hmac?
                          param(otp_setup_raw_param)
                        else
                          secret
                        end

            # Validation Step 2: Password verification
            unless two_factor_password_match?(param(password_param))
              Auth::Logging.log_auth_event(
                :mfa_setup_failure,
                level: :warn,
                log_metric: true,
                account_id: account_id,
                email: account[:email],
                failure_reason: :invalid_password,
                message: 'Password verification failed during MFA setup',
              )
              throw_error_reason(:invalid_password, invalid_password_error_status, password_param, invalid_password_message)
            end

            # Validation Step 3: OTP code verification
            unless otp_valid_code?(param(otp_auth_param))
              Auth::Logging.log_auth_event(
                :mfa_setup_failure,
                level: :warn,
                log_metric: true,
                account_id: account_id,
                email: account[:email],
                failure_reason: :invalid_otp_code,
                message: 'OTP code verification failed (incorrect code or timing issue)',
              )
              throw_error_reason(:invalid_otp_auth_code, invalid_key_error_status, otp_auth_param, otp_invalid_auth_code_message)
            end

            # All validations passed - proceed with setup
            transaction do
              before_otp_setup
              otp_add_key(new_secret)
              unless two_factor_authenticated?
                two_factor_update_session('totp')
              end
              after_otp_setup
            end

            otp_setup_response
          end
        end
      end
    end
  end
end
