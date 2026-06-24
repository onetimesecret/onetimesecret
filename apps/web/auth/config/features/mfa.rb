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
    # Configuration constants
    RECOVERY_CODES_LIMIT    = 4
    OTP_AUTH_FAILURES_LIMIT = 7

    def self.configure(auth)
      # Multi-Factor Authentication (conditionally enabled via ENV in config.rb)
      auth.enable :two_factor_base
      auth.enable :otp             # Time-based One-Time Password (TOTP)
      auth.enable :recovery_codes  # Backup codes for MFA

      # MFA Configuration — issuer from brand config so client QR and server agree
      auth.otp_issuer Onetime::CustomDomain::BrandSettingsConstants.global_defaults[:totp_issuer]
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
      auth.otp_auth_failures_limit OTP_AUTH_FAILURES_LIMIT

      # Recovery codes configuration
      auth.auto_add_recovery_codes? true  # Automatically generate recovery codes
      auth.recovery_codes_limit RECOVERY_CODES_LIMIT

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

      # Recovery codes are CSPRNG-backed (SecureRandom) 64-bit values rendered
      # in base36 — roughly 13 characters, e.g. "3w5e11264sgsf", with ~1.8e19
      # (2**64) possibilities. 64 bits is deliberately chosen over a longer
      # token: recovery codes are verified server-side, are rate-limited, and
      # are bound to a single account, so they are not an offline-guessable
      # artifact — and a shorter code is far less error-prone for a user to type
      # when they are locked out. (Familia labels the 64-bit tier "trace"; the
      # higher tiers carry the same "resist intentional guessing" caveat and
      # only buy length, so we stay at 64-bit by design.)
      auth.new_recovery_code do
        Familia.generate_trace_id
      end
    end
  end
end
