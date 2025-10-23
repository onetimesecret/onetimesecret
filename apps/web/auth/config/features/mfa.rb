# apps/web/auth/config/features/mfa.rb

module Auth
  module Config
    module Features
      module MFA
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Multi-Factor Authentication
            enable :otp  # Time-based One-Time Password (TOTP)
            enable :recovery_codes  # Backup codes for MFA

            # Table column configurations
            # All Rodauth tables use account_id as FK, not id
            otp_keys_table :account_otp_keys
            otp_keys_id_column :account_id
            recovery_codes_table :account_recovery_codes
            recovery_codes_id_column :account_id

            # MFA Configuration
            otp_issuer 'OneTimeSecret'
            otp_setup_param 'otp_setup'
            otp_auth_param 'otp_code'

            # Recovery codes configuration
            recovery_codes_column :code
            auto_add_recovery_codes? true  # Automatically generate recovery codes

            # Handle JSON-only OTP setup flow:
            # Step 1: POST /auth/otp-setup with {} -> returns secret, QR code
            # Step 2: POST /auth/otp-setup with {otp_code: "123456"} -> verifies and completes setup
            before_otp_setup_route do
              if json_request? && param_or_nil(otp_auth_param).nil?
                # Initial setup request - no verification code provided

                # Check if we already have a secret in session (user refreshed page)
                # If not, generate a new one
                existing_secret = session[:otp_setup_secret]
                new_secret = existing_secret || otp_new_secret

                # Store secret in session for the verification request
                # This persists across requests so the same secret is used
                session[:otp_setup_secret] = new_secret

                # Also set the temporary key for Rodauth's validation
                otp_tmp_key(new_secret)

                # Build and return JSON response
                response.status = 200
                response.headers['Content-Type'] = 'application/json'
                response.write({
                  success: 'TOTP setup initiated',
                  secret: new_secret,
                  provisioning_uri: otp_provisioning_uri,
                  qr_code: otp_qr_code
                }.to_json)

                # Halt route processing
                request.halt
              end
              # If otp_code is provided, continue with normal verification flow
            end

            # Clear the temporary secret from session after successful setup
            after_otp_setup do
              session.delete(:otp_setup_secret)
            end
          end
        end
      end
    end
  end
end
