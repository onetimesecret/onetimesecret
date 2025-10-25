# apps/web/auth/config/features/security.rb

module Auth::Config::Features
  # Placeholder for Rodauth overrides
  #
  module RodauthOverrides
    def self.configure(auth)

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

      # Override OTP validation instance method
      auth.auth_class_eval do
        # Store original method
        alias_method :_original_otp_valid_code?, :otp_valid_code?

        # TODO: Do we still need this now that we've resolved the
        # context issues with how we organized the code?
        #
        def otp_valid_code?(oacode)
          # Always log when this method is called
          Onetime.auth_logger.debug '[MFA] otp_valid_code? called',
            code: oacode,
            json: json_request?,
            post: request.post?,
            path: request.path_info,
            setup_route: otp_setup_route,
            auth_route: otp_auth_route,
            session_raw: session[:otp_setup_raw]

          # During setup with HMAC, use the session-stored HMAC secret
          # Note: path_info has leading slash, routes don't
          if json_request? && request.post? &&
              request.path_info == "/#{otp_setup_route}" &&
              session[:otp_setup_raw]

            require 'rotp'
            # CRITICAL: Use HMAC version for setup validation, not raw
            # The QR code contains the HMAC version, so validate against that
            hmac_key = otp_keys_use_hmac? ? otp_hmac_secret(session[:otp_setup_raw]) : session[:otp_setup_raw]
            totp = ROTP::TOTP.new(hmac_key)
            expected = totp.now

            # Debug logging
            Onetime.auth_logger.debug '[MFA Setup] OTP validation',
              provided_code: oacode,
              expected_code: expected,
              raw_secret: session[:otp_setup_raw],
              hmac_secret_sample: "#{hmac_key[0..3]}...#{hmac_key[-4..-1]}",
              codes_match: (oacode == expected),
              drift_check: totp.verify(oacode, drift_behind: 15, drift_ahead: 15)

            # Use drift tolerance for validation
            result = totp.verify(oacode, drift_behind: 15, drift_ahead: 15)
            return !!result
          end

          # During login with HMAC, compute HMAC from stored raw key
          if json_request? && request.post? &&
              request.path_info == "/#{otp_auth_route}" &&
              otp_keys_use_hmac?

            raw_key = db[otp_keys_table].where(otp_keys_id_column => account_id).get(otp_keys_column)
            if raw_key
              require 'rotp'
              # Compute HMAC version - this is what the authenticator app has
              hmac_key = otp_hmac_secret(raw_key)
              totp = ROTP::TOTP.new(hmac_key, issuer: otp_issuer)
              expected = totp.now

              Onetime.auth_logger.debug '[MFA Login] OTP validation',
                provided_code: oacode,
                expected_code: expected,
                raw_key_sample: "#{raw_key[0..3]}...#{raw_key[-4..-1]}",
                hmac_key_sample: "#{hmac_key[0..3]}...#{hmac_key[-4..-1]}",
                codes_match: (oacode == expected),
                drift_check: totp.verify(oacode, drift_behind: 15, drift_ahead: 15)

              # Use drift tolerance for validation
              result = totp.verify(oacode, drift_behind: 15, drift_ahead: 15)
              return !!result
            end
          end

          # Otherwise use default validation
          _original_otp_valid_code?(oacode)
        end
      end

      # Custom: Get WebAuthn credentials list for account
      # Used by frontend to show registered devices
      auth_class_eval do
        def webauthn_credentials_for_account
          db[webauthn_keys_table]
            .where(webauthn_keys_account_id_column => account_id)
            .select(
              Sequel.as(webauthn_keys_webauthn_id_column, :id),
              webauthn_keys_last_use_column,
              webauthn_keys_sign_count_column
            )
            .all
        end
      end

    end
  end
end
