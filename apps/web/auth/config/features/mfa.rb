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
          end
        end
      end
    end
  end
end
