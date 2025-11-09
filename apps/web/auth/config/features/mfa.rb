# apps/web/auth/config/features/mfa.rb
#
# frozen_string_literal: true

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

      # MFA Configuration
      auth.otp_issuer 'OneTimeSecret'
      auth.otp_setup_param 'otp_setup'
      auth.otp_setup_raw_param 'otp_raw_secret'
      auth.otp_auth_param 'otp_code'

      # If this is disabled after having been enabled, existing OTP
      # keys will be invalidated.
      auth.otp_keys_use_hmac? true

      # Password requirements for MFA modifications
      # SECURITY: Require password confirmation to disable MFA
      auth.two_factor_modifications_require_password? true
      auth.modifications_require_password? true

      # OTP Lockout Configuration
      # Default is 5 attempts with permanent lockout - too harsh for production
      # Industry standard: 10-20 attempts before lockout, with time-based reset
      #
      # We use a higher threshold because:
      # - Users make legitimate mistakes (typos, wrong app, clock sync)
      # - Recovery codes provide the primary escape mechanism
      # - Our MFA recovery flow provides email-based reset
      # - Too-strict lockout creates support burden
      auth.otp_auth_failures_limit 10  # Up from default 5

      # Recovery codes configuration
      auth.auto_add_recovery_codes? true  # Automatically generate recovery codes

      # Critical: Orphaned recovery codes create a "zombie MFA state"
      # where Rodauth still considers MFA active because recovery codes
      # count as an authentication method.
      auth.auto_remove_recovery_codes? true

      # Require second factor during login if user has MFA setup
      #
      # NOTE: The require_two_factor_authenticated method is called in route blocks,
      # not in configuration. The login flow already handles MFA detection via the
      # after_login hook in apps/web/auth/config/hooks/login.rb which checks
      # uses_two_factor_authentication? and sets json_response[:mfa_required] = true

      # Generate 8-character alphanumeric codes (like: 4k9m-x2pq)
      # This provides ~1.7 billion possible codes (36^8)
      auth.new_recovery_code do
        Familia.generate_trace_id
      end
    end
  end
end
