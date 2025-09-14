# frozen_string_literal: true

module Auth
  module Config
    module Features
      module MFA
        def self.configure(rodauth_config)
          rodauth_config.instance_eval do
            # Multi-Factor Authentication
            enable :otp  # Time-based One-Time Password (TOTP)
            enable :recovery_codes  # Backup codes for MFA
            enable :remember  # "Remember me" functionality
            enable :verify_account  # Disabled until email is properly configured

            # Remember cookie configuration (requires remember feature)
            remember_cookie_key 'onetime.remembers'

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
