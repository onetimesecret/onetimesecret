# apps/web/auth/config/features/mfa.rb

module Auth::Config::Features
  # Handle JSON-only OTP setup flow with HMAC:
  # When HMAC is enabled, Rodauth uses a two-step process:
  # Step 1: POST /auth/otp-setup -> generates secret, returns setup data
  # Step 2: POST /auth/otp-setup with {otp_code, otp_setup, otp_raw_secret} -> verifies
  #
  # @see https://rodauth.jeremyevans.net/rdoc/files/doc/otp_rdoc.html
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

      # If this is disabled after having been enabled, existing OTP
      # keys will be invalidated.
      auth.otp_keys_use_hmac? true

      # auth.otp_setup_redirect ''

      # Password requirements for MFA modifications
      # In JSON API mode, password confirmation adds friction without security benefit
      # since the user must already be authenticated to access these routes
      auth.two_factor_modifications_require_password? false

      # Recovery codes configuration
      auth.recovery_codes_column :code
      auth.auto_add_recovery_codes? true  # Automatically generate recovery codes

      # Require second factor during login if user has MFA setup
      #
      # TODO: Fix this NoMethodError. It's the correct method name but
      # we're obviously not calling it the right way.
      #
      # auth.require_two_factor_authenticated do
      #   # Check if account has OTP configured
      #   db[otp_keys_table].where(otp_keys_id_column => account_id).count > 0
      # end
    end
  end
end
