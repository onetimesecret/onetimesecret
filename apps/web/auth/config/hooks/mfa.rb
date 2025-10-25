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
      # HOOK: Before OTP Authentication Route (Login Verification)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires when a user attempts to verify their OTP code during login.
      # It ensures proper HMAC secret handling and adds diagnostic logging.
      #
      auth.before_otp_auth_route do
        if json_request?
          # Retrieve the stored HMAC secret from database
          hmac_key = db[otp_keys_table].where(otp_keys_id_column => account_id).get(otp_keys_column)

          if hmac_key
            Onetime.auth_logger.debug '[MFA Login] OTP authentication attempt',
              account_id: account_id,
              has_hmac_key: hmac_key.to_s.empty?,
              hmac_key_sample: "#{hmac_key[0..3]}...#{hmac_key[-4..-1]}",
              otp_code_provided: param(otp_auth_param).to_s.empty?
          else
            Onetime.auth_logger.warn '[MFA Login] No OTP key found in database',
              account_id: account_id
          end
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
              request: request
            )
            session.delete(:awaiting_mfa)
          end
        end
      end

      # ========================================================================
      # HOOK: After Successful OTP Authentication (Currently Disabled)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook would fire after a user successfully enters their 6-digit
      # OTP code during login. It's the final step in the authentication flow:
      #
      # Login Flow with MFA:
      # 1. User submits username/password → basic auth succeeds
      # 2. System detects MFA enabled → sets session['mfa_pending'] = true
      # 3. User redirected to OTP verification page
      # 4. User enters 6-digit code from authenticator app
      # 5. **THIS HOOK FIRES** → completes session sync and grants full access
      #
      # Purpose:
      # - Completes deferred session synchronization from initial login
      # - Removes 'mfa_pending' flag from session
      # - Marks user as fully authenticated with all permissions
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

      # ========================================================================
      # HOOK: Before OTP Setup Route (Handles Both Setup Steps)
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This single hook handles BOTH steps of MFA setup for JSON API clients.
      # It determines which step based on presence of OTP code in request.
      #
      # The hook customizes Rodauth's default HTML form-based flow to work
      # with JSON API requests from the Vue frontend.
      #
      auth.before_otp_setup_route do
        if json_request?
          # Determine which step based on presence of OTP code parameter
          # param_or_nil(otp_auth_param) checks for the "otp" field
          if param_or_nil(otp_auth_param).nil?
            # ================================================================
            # STEP 1: INITIAL SETUP REQUEST
            # ================================================================
            #
            # USER ACTION: User clicks "Enable 2FA" button in settings
            # REQUEST: POST /otp-setup (no OTP code in body)
            #
            # WHAT HAPPENS:
            # 1. Generate cryptographic secret for TOTP algorithm
            # 2. Store secrets in session for verification in step 2
            # 3. Create QR code containing secret and account info
            # 4. Return setup data to frontend for display
            #
            # USER SEES: QR code, manual entry code, instructions

            # Check for existing setup in progress (handles page refresh)
            raw_secret = session[:otp_setup_raw]

            # Generate new secret if none exists in session
            unless raw_secret
              # Create base32-encoded secret (16 chars, ~80 bits entropy)
              # Example: "JBSWY3DPEHPK3PXP"
              raw_secret = otp_new_secret
              session[:otp_setup_raw] = raw_secret

              Onetime.auth_logger.debug '[MFA Setup Step 1] Generated new OTP secret',
                raw_secret_length: raw_secret.length,
                raw_secret_sample: "#{raw_secret[0..3]}...#{raw_secret[-4..-1]}"

              # Security layer: Generate HMAC version if enabled
              # HMAC prevents secret tampering and provides additional validation
              if otp_keys_use_hmac?
                hmac_secret = otp_hmac_secret(raw_secret)
                session[:otp_setup_hmac] = hmac_secret

                Onetime.auth_logger.debug '[MFA Setup Step 1] Generated HMAC secret',
                  hmac_secret_length: hmac_secret.length,
                  hmac_secret_sample: "#{hmac_secret[0..3]}...#{hmac_secret[-4..-1]}"
              end
            end

            # Configure Rodauth's internal OTP validation
            # CRITICAL: Must use raw secret - ROTP validates against this
            otp_tmp_key(raw_secret)

            # Prepare JSON response for frontend
            response.status = 200
            response.headers['Content-Type'] = 'application/json'

            # Generate data for authenticator app configuration:
            # 1. Provisioning URI: otpauth://totp/OneTime:user@email.com?secret=...
            #    Contains secret, issuer, account name for one-click setup
            # 2. QR Code SVG: Visual encoding of provisioning URI
            #    User scans this with authenticator app camera
            prov_uri = otp_provisioning_uri
            qr_code_svg = otp_qr_code

            # Extract secret from provisioning URI for verification
            uri_secret = prov_uri.match(/secret=([^&]+)/)[1] rescue nil
            expected_secret = otp_keys_use_hmac? ? session[:otp_setup_hmac] : raw_secret
            Onetime.auth_logger.debug '[MFA Setup Step 1] Provisioning URI generated',
              uri_contains_expected: uri_secret == expected_secret,
              expected_type: otp_keys_use_hmac? ? 'HMAC' : 'raw',
              uri_secret_sample: uri_secret ? "#{uri_secret[0..3]}...#{uri_secret[-4..-1]}" : 'nil'

            # Build response payload
            # NOTE: When HMAC is enabled, the QR code and manual entry secret should both
            # contain the HMAC version (what authenticator apps use), not the raw secret.
            # The raw secret is stored in the database for security.
            manual_entry_secret = otp_keys_use_hmac? ? session[:otp_setup_hmac] : raw_secret

            result = {
              secret: manual_entry_secret,     # For manual entry (HMAC if enabled)
              provisioning_uri: prov_uri,      # For authenticator parsing
              qr_code: qr_code_svg            # SVG for visual display
            }

            # Include HMAC security parameters if enabled
            # These will be validated in step 2 to ensure session integrity
            if otp_keys_use_hmac?
              result[otp_setup_param] = session[:otp_setup_hmac]
              result[otp_setup_raw_param] = raw_secret
            end

            Onetime.auth_logger.debug '[MFA Setup Step 1] Response payload',
              has_secret: !result[:secret].nil?,
              has_prov_uri: !result[:provisioning_uri].nil?,
              has_qr_code: !result[:qr_code].nil?,
              has_otp_setup: !result[otp_setup_param.to_sym].nil?,
              has_otp_raw_secret: !result[otp_setup_raw_param.to_sym].nil?

            # Send response and stop Rodauth's default processing
            response.write(result.to_json)
            request.halt  # Prevents Rodauth from rendering HTML form
          else
            # ================================================================
            # STEP 2: VERIFICATION REQUEST
            # ================================================================
            #
            # USER ACTION: User enters 6-digit code from authenticator app
            # REQUEST: POST /otp-setup with body: { "otp": "123456", ... }
            #
            # WHAT HAPPENS:
            # 1. Validate HMAC parameters match session (prevents tampering)
            # 2. Retrieve raw secret from session
            # 3. Rodauth validates OTP code using ROTP library
            # 4. If valid, Rodauth stores HMAC secret to database
            # 5. Cleanup hook removes temporary session data
            #
            # VALIDATION FLOW:
            # - ROTP generates expected code from raw secret + current time
            # - Compares user's code with expected code (allows ±1 time step)
            # - Success: MFA enabled, user sees confirmation
            # - Failure: Error message, user can retry
            #
            if otp_keys_use_hmac? && session[:otp_setup_raw]
              # Security check: Validate client sent correct HMAC parameters
              # This ensures the request matches the session that initiated setup
              provided_raw = param_or_nil(otp_setup_raw_param)
              provided_hmac = param_or_nil(otp_setup_param)

              # Log validation attempt for debugging
              Onetime.auth_logger.debug '[MFA] OTP verification attempt',
                session_raw: session[:otp_setup_raw],
                session_hmac: session[:otp_setup_hmac],
                provided_raw: provided_raw,
                provided_hmac: provided_hmac,
                params_match: (provided_raw == session[:otp_setup_raw] && provided_hmac == session[:otp_setup_hmac])

              # Verify HMAC parameters match session
              # If mismatch, fall through to Rodauth's error handling
              unless provided_raw == session[:otp_setup_raw] &&
                      provided_hmac == session[:otp_setup_hmac]
                # Rodauth will handle error response generation
                # User will see "Invalid setup parameters" or similar
              end

              # Configure Rodauth for OTP validation
              # CRITICAL: Use HMAC secret - authenticator app generates codes from this
              # (The QR code contains the HMAC secret, not the raw secret, when HMAC is enabled)
              # After validation, Rodauth stores the raw secret to database
              otp_tmp_key(session[:otp_setup_hmac])

              Onetime.auth_logger.debug '[MFA] Set otp_tmp_key for validation',
                tmp_key: session[:otp_setup_hmac],
                otp_code: param(otp_auth_param)
            end
          end
        end
      end

      # ========================================================================
      # HOOK: After OTP Setup Complete
      # ========================================================================
      #
      # USER JOURNEY CONTEXT:
      # This hook fires immediately after Rodauth successfully validates the
      # OTP code and stores the HMAC secret to the database.
      #
      # At this point:
      # - User's OTP code was correct (matched ROTP validation)
      # - HMAC secret has been written to accounts.otp_key column
      # - User's account is now MFA-enabled
      #
      # Purpose: Clean up temporary session data used during setup
      # - Remove raw secret (no longer needed, HMAC version in DB)
      # - Remove HMAC secret (no longer needed, already persisted)
      #
      # USER EXPERIENCE: User sees "2FA enabled successfully" message
      #
      auth.after_otp_setup do
        session.delete(:otp_setup_raw)
        session.delete(:otp_setup_hmac)
      end

    end
  end
end
