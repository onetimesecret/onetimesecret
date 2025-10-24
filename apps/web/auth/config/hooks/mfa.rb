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

      #
      # Hook: After successful OTP authentication
      #
      # This hook is triggered after successful two-factor (OTP) authentication.
      # Complete the full session sync that was deferred during login and mark
      # as fully authenticated.
      #
      # auth.after_otp_auth do
      #   OT.info "[auth] OTP authentication successful for: #{account[:email]}"

      #   if session['mfa_pending']
      #     OT.info "[auth] Completing deferred session sync after MFA"
      #     Onetime::ErrorHandler.safe_execute('sync_session_after_mfa',
      #       account_id: account_id,
      #       email: account[:email],
      #     ) do
      #       Handlers.sync_session_after_login(account, account_id, session, request)
      #       session.delete('mfa_pending')
      #     end
      #   end
      # end

      # Customize the route handling to support JSON API
      auth.before_otp_setup_route do
        if json_request?
          # Check if this is step 1 (no OTP code) or step 2 (with OTP code)
          if param_or_nil(otp_auth_param).nil?
            # Step 1: Initial setup request - generate secret and return setup data

            # Check session for existing setup in progress
            raw_secret = session[:otp_setup_raw]

            # Generate new secret if none in session
            unless raw_secret
              raw_secret = otp_new_secret
              session[:otp_setup_raw] = raw_secret

              # Generate HMAC version if HMAC is enabled
              if otp_keys_use_hmac?
                hmac_secret = otp_hmac_secret(raw_secret)
                session[:otp_setup_hmac] = hmac_secret
              end
            end

            # Set temporary key for Rodauth validation
            # This must be the raw secret, as that's what ROTP validates against
            otp_tmp_key(raw_secret)

            # Build response with setup data
            response.status = 200
            response.headers['Content-Type'] = 'application/json'

            # Generate provisioning URI and QR code with raw secret
            # The authenticator needs the raw secret to generate codes
            prov_uri = otp_provisioning_uri
            qr_code_svg = otp_qr_code

            result = {
              secret: raw_secret,
              provisioning_uri: prov_uri,
              qr_code: qr_code_svg
            }

            # Include HMAC parameters if HMAC is enabled
            if otp_keys_use_hmac?
              result[otp_setup_param] = session[:otp_setup_hmac]
              result[otp_setup_raw_param] = raw_secret
            end

            response.write(result.to_json)
            request.halt
          else
            # Step 2: Verification request - validate HMAC parameters if enabled
            if otp_keys_use_hmac? && session[:otp_setup_raw]
              # Ensure the client sent back the correct HMAC values
              provided_raw = param_or_nil(otp_setup_raw_param)
              provided_hmac = param_or_nil(otp_setup_param)

              # Debug logging
              Onetime.auth_logger.debug '[MFA] OTP verification attempt',
                session_raw: session[:otp_setup_raw],
                session_hmac: session[:otp_setup_hmac],
                provided_raw: provided_raw,
                provided_hmac: provided_hmac,
                params_match: (provided_raw == session[:otp_setup_raw] && provided_hmac == session[:otp_setup_hmac])

              # If parameters are missing or don't match session, fail
              unless provided_raw == session[:otp_setup_raw] &&
                      provided_hmac == session[:otp_setup_hmac]
                # Let Rodauth's normal error handling take over
                # This will generate proper error response
              end

              # Set the temporary key for Rodauth's validation
              # CRITICAL: This must be the raw secret for OTP validation
              otp_tmp_key(session[:otp_setup_raw])

              Onetime.auth_logger.debug '[MFA] Set otp_tmp_key for validation',
                tmp_key: session[:otp_setup_raw],
                otp_code: param(otp_auth_param)
            end
          end
        end
      end

      # Clear the setup session data after successful setup
      auth.after_otp_setup do
        session.delete(:otp_setup_raw)
        session.delete(:otp_setup_hmac)
      end

    end
  end
end
