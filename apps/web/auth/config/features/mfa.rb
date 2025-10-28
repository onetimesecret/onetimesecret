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

      # CRITICAL: Disable password requirement for ALL modification operations
      # This ensures that during MFA setup, we don't require re-authentication
      # between the initial setup (QR code generation) and verification (code submission)
      auth.modifications_require_password? false

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

      # Require second factor during login if user has MFA setup
      #
      # NOTE: The require_two_factor_authenticated method is called in route blocks,
      # not in configuration. The login flow already handles MFA detection via the
      # after_login hook in apps/web/auth/config/hooks/login.rb which checks
      # uses_two_factor_authentication? and sets json_response[:mfa_required] = true
    end
  end
end


# ==============================================================================
# USER JOURNEY: MULTI-FACTOR AUTHENTICATION (MFA) SETUP
# ==============================================================================
#
# This file configures Rodauth hooks that intercept and customize the MFA flow
# for JSON API requests. The user's journey through MFA setup follows this path:
#
# 1. USER INITIATES MFA SETUP (before_otp_setup_route - Step 1)
#    - User requests POST /otp-setup without an OTP code
#    - Server generates a new TOTP secret (base32 encoded, 16 chars)
#    - If otp_keys_use_hmac enabled:
#      * Raw secret stored in session as :otp_setup_raw
#      * HMAC parameters stored in session as :otp_setup
#    - Response includes raw secret, provisioning URI, QR code SVG
#
# 2. USER SCANS QR CODE
#    - User opens authenticator app (Google Authenticator, Authy, etc.)
#    - Scans QR code or manually enters the raw secret
#    - Authenticator begins generating 6-digit codes every 30 seconds
#
# 3. USER VERIFIES SETUP (Step 2)
#    - User submits POST /otp-setup WITH an OTP code from authenticator
#    - Server validates HMAC parameters against session
#    - Server retrieves raw secret from session
#    - Rodauth validates OTP code against raw secret using ROTP library
#    - If valid, Rodauth stores the HMAC-secured key to database
#      (not the HMAC secret itself, but the key derived using HMAC)
#    - Flow continues to after_otp_setup hook
#
# 4. CLEANUP (after_otp_setup)
#    - Server removes temporary session data
#    - MFA setup complete - user's account now requires 2FA for login
#
#
# ==============================================================================

__END__

curl -X POST https://dev.onetime.dev/auth/otp-setup \
  -H "Content-Type: application/json" \
  -b 'onetime.session=e6c0a5e9fba3cb30f03476b0e19cffdaf24737499461756ce86035895e42384f' \
  -v -k

  curl 'https://dev.onetime.dev/auth/otp-setup' \
    -H 'accept: application/json' \
    -H 'accept-language: en' \
    -H 'cache-control: no-cache' \
    -H 'content-type: application/json' \

    -H 'dnt: 1' \
    -H 'o-shrimp;' \
    -H 'origin: https://dev.onetime.dev' \
    -H 'pragma: no-cache' \
    -H 'priority: u=1, i' \
    -H 'sec-ch-ua: "Chromium";v="141", "Not?A_Brand";v="8"' \
    -H 'sec-ch-ua-mobile: ?0' \
    -H 'sec-ch-ua-platform: "macOS"' \
    -H 'sec-fetch-dest: empty' \
    -H 'sec-fetch-mode: cors' \
    -H 'sec-fetch-site: same-origin' \
    -H 'user-agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36' \
    --data-raw '{}'
