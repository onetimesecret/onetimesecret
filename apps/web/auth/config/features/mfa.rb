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

      # Password requirements for MFA and account modifications
      #
      # SECURITY: Accounts that HAVE a password must still confirm it for
      # two-factor modifications (otp-disable, webauthn-setup, webauthn-remove
      # — all gated through two_factor_password_match?) and for the
      # password-gated account routes (change-password, change-login,
      # close-account). Password-LESS accounts (SSO-only: no password in
      # account_password_hashes AND none in Redis — the accounts table has no
      # password column) are exempt because they CANNOT satisfy a password
      # gate; a hard `true` here made passkey setup/removal and account
      # management impossible for them.
      #
      # Rodauth's own default is bare has_password?, but that reads ONLY
      # account_password_hashes — it cannot see the pre-migration cohort whose
      # password still lives in Redis (config/overrides/password_migration.rb
      # verifies those transparently in password_match?). Those users CAN
      # satisfy the gate, so they MUST be held to it: exempting them would let
      # a hijacked session change/strip credentials with zero re-auth, and
      # they may never do a password login that writes the Rodauth hash
      # (magic-link/SSO users), so "the next login migrates it" never comes.
      # Hence: has_password? OR the shared Redis-side probe (same helper the
      # SSO-linking interstitial uses; fail-CLOSED on probe error — treat the
      # account as password-holding rather than silently exempting it).
      #
      # NOTE: this module only loads when AUTH_MFA_ENABLED=true (config.rb).
      # With MFA off, Rodauth's bare has_password? default applies, which
      # exempts the Redis-legacy cohort in that configuration (pre-existing
      # behavior, unchanged here).
      # rubocop:disable Lint/NestedMethodDefinition -- auth_class_eval evaluates in Auth class context
      auth.auth_class_eval do
        # Can this account be challenged for a password? True when a Rodauth
        # argon2 hash exists (has_password?) or when a legacy password is
        # still resident in Redis awaiting migration. Used by BOTH
        # modifications_require_password? and
        # two_factor_modifications_require_password? below.
        def password_modification_challengeable?
          return true if has_password?

          acct  = account || account_from_session
          email = acct && acct[:email]
          return false unless email

          Auth::Config::Hooks::OmniAuth.account_has_challengeable_password?(
            db[password_hash_table].where(password_hash_id_column => acct[account_id_column]),
            OT::Utils.normalize_email(email),
            'password_modification_gate',
            error_result: true, # fail closed: outage != password-less
          )
        end
      end
      # rubocop:enable Lint/NestedMethodDefinition
      auth.modifications_require_password? { password_modification_challengeable? }
      auth.two_factor_modifications_require_password? { password_modification_challengeable? }

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
