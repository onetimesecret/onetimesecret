# apps/web/auth/config/features/mfa.rb

module Auth
  module Config
    module Features
      module MFA
        def self.configure(auth)

          # Multi-Factor Authentication
          # enable :otp  # Time-based One-Time Password (TOTP)
          # enable :recovery_codes  # Backup codes for MFA

          # Table column configurations
          # All Rodauth tables use account_id as FK, not id
          auth.otp_keys_table :account_otp_keys
          auth.otp_keys_id_column :account_id
          auth.recovery_codes_table :account_recovery_codes
          auth.recovery_codes_id_column :account_id

          # MFA Configuration
          auth.otp_issuer 'OneTimeSecret'
          auth.otp_setup_param 'otp_setup'
          auth.otp_setup_raw_param 'otp_raw_secret'
          auth.otp_auth_param 'otp_code'

          # Password requirements for MFA modifications
          # In JSON API mode, password confirmation adds friction without security benefit
          # since the user must already be authenticated to access these routes
          auth.two_factor_modifications_require_password? false

          # Recovery codes configuration
          auth.recovery_codes_column :code
          auth.auto_add_recovery_codes? true  # Automatically generate recovery codes

          # Require second factor during login if user has MFA setup
          auth.require_two_factor_authenticated do
            # Check if account has OTP configured
            db[otp_keys_table].where(otp_keys_id_column => account_id).count > 0
          end

          # After successful password authentication, check for MFA
          auth.after_login do
            # If user has MFA enabled, don't mark as fully authenticated yet
            if db[otp_keys_table].where(otp_keys_id_column => account_id).count > 0
              # Set flag that second factor is required
              session[:awaiting_mfa] = true

              # For JSON mode, return different success message
              if json_request?
                json_response[:mfa_required] = true
                json_response[:mfa_auth_url] = "/#{otp_auth_route}"
                # Don't set authenticated_at yet
              end
            else
              # No MFA, proceed normally
              session[:awaiting_mfa] = false
            end
          end

          # After successful OTP authentication, mark as fully authenticated
          auth.after_otp_auth do
            session.delete(:awaiting_mfa)
          end

          # Override authenticated? to require MFA completion
          auth.auth_class_eval do
            def require_authentication
              if session[:awaiting_mfa]
                set_redirect_error_flash require_mfa_error_flash
                redirect otp_auth_route
              end
              super
            end
          end

          # Handle JSON-only OTP setup flow with HMAC:
          # When HMAC is enabled, Rodauth uses a two-step process:
          # Step 1: POST /auth/otp-setup -> generates secret, returns setup data
          # Step 2: POST /auth/otp-setup with {otp_code, otp_setup, otp_raw_secret} -> verifies

          # Customize the route handling to support JSON API
          before_otp_setup_route do
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

          # Override OTP validation instance method
          auth_class_eval do
            # Store original method
            alias_method :_original_otp_valid_code?, :otp_valid_code?

            def otp_valid_code?(oacode)
              # Always log when this method is called
              Onetime.auth_logger.debug '[MFA] otp_valid_code? called',
                code: oacode,
                json: json_request?,
                post: request.post?,
                path: request.path_info,
                setup_route: otp_setup_route,
                session_raw: session[:otp_setup_raw]

              # During setup with HMAC, use the session-stored raw secret
              # Note: path_info has leading slash, setup_route doesn't
              if json_request? && request.post? &&
                  request.path_info == "/#{otp_setup_route}" &&
                  session[:otp_setup_raw]

                require 'rotp'
                totp = ROTP::TOTP.new(session[:otp_setup_raw])
                expected = totp.now

                # Debug logging
                Onetime.auth_logger.debug '[MFA] OTP validation check',
                  provided_code: oacode,
                  expected_code: expected,
                  secret: session[:otp_setup_raw],
                  codes_match: (oacode == expected),
                  drift_check: totp.verify(oacode, drift_behind: 15, drift_ahead: 15)

                # Use drift tolerance for validation
                result = totp.verify(oacode, drift_behind: 15, drift_ahead: 15)
                return !!result
              end

              # Otherwise use default validation
              _original_otp_valid_code?(oacode)
            end
          end

          # Clear the setup session data after successful setup
          after_otp_setup do
            session.delete(:otp_setup_raw)
            session.delete(:otp_setup_hmac)
          end
        end
      end
    end
  end
end
