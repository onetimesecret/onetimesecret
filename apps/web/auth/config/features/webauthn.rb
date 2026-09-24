# apps/web/auth/config/features/webauthn.rb
#
# frozen_string_literal: true

# Public-host resolution shared with the Rodauth base_url override (#4221) and
# host-allowlisted for finding G-01. Defines Auth::PublicHost.
require_relative '../../lib/public_host'

module Auth::Config::Features
  module WebAuthn
    def self.configure(auth)
      # WebAuthn features. This module itself is conditionally loaded via
      # AUTH_WEBAUTHN_ENABLED (config.rb); the two sub-features are their own
      # opt-ins, read through the same config path as the main flag
      # (full.features in etc/defaults/auth.defaults.yaml, rendered from
      # AUTH_WEBAUTHN_VERIFY_ACCOUNT / AUTH_WEBAUTHN_AUTOFILL with == 'true'
      # semantics — only the literal string 'true' enables; default OFF).
      auth.enable :webauthn, :webauthn_login, :webauthn_modify_email
      auth.enable :webauthn_verify_account if Onetime.auth_config.webauthn_verify_account_enabled?
      auth.enable :webauthn_autofill if Onetime.auth_config.webauthn_autofill_enabled?

      # WebAuthn configuration.
      #
      # rp_id and origin MUST match the host the browser is actually ON, so
      # host derivation routes through Auth::PublicHost — the one audited place
      # for it (finding G-16). On a registered custom domain the resolver swaps
      # in the display domain (the origin the passkey was registered against);
      # otherwise it declines and we keep the request host, which
      # StripForwardedHost has already cleansed of any client-supplied
      # forwarded authority, so dev/staging/prod on the canonical host keep
      # working. These are verify-only values (a mismatch fails the ceremony,
      # it does not redirect a link), so the request-host fallback is the safe
      # default here rather than the canonical host.
      auth.webauthn_rp_id do
        Auth::PublicHost.resolve(request.env) || request.host
      end

      auth.webauthn_origin do
        # Full origin for WebAuthn challenge verification
        Auth::PublicHost.base_url(request.env) ||
          "#{request.scheme}://#{request.host_with_port}"
      end

      auth.webauthn_rp_name 'OnetimeSecret'

      # WebAuthn challenge configuration
      auth.webauthn_setup_timeout 60_000  # 60 seconds for user interaction during setup
      auth.webauthn_auth_timeout 60_000   # 60 seconds for user interaction during auth

      # User verification: preferred (use if available, but don't require)
      # This enables Face ID, Touch ID, Windows Hello
      auth.webauthn_user_verification 'preferred'

      # A passkey LOGIN whose authenticator reports user verification counts as
      # both factors natively (authenticated_by = ['webauthn',
      # 'webauthn-verification'] before after_login fires — gem
      # webauthn_login.rb). Policy: a passkey first factor fully authenticates.
      # The after_login hook (hooks/login.rb) extends the same treatment to the
      # non-UV residual (e.g. a security key without PIN), so this flag is the
      # honest/native half of that pair. Note the gem pins the login-ceremony
      # user verification to 'preferred' when this is on — identical to the
      # setting above, so no behavior change there.
      auth.webauthn_login_user_verification_additional_factor? true

      # Authenticator selection: Rodauth's default is used ON PURPOSE —
      #   {'requireResidentKey' => false,
      #    'userVerification' => webauthn_user_verification}
      # It does not set authenticatorAttachment at all, which already permits
      # both platform (Face ID, Touch ID, Windows Hello) and cross-platform
      # (YubiKey) authenticators. A previous override returned
      # { authenticatorAttachment: nil } to express that same intent, but the
      # whole-hash replacement silently dropped requireResidentKey and
      # userVerification from credential-creation options (decoupling them
      # from the setting above) and broke webauthn_autofill's super.merge
      # composition. Do not override webauthn_authenticator_selection without
      # carrying the default keys forward.

      # Routes (relative to /auth mount point)
      auth.webauthn_setup_route 'webauthn-setup'
      auth.webauthn_auth_route 'webauthn-auth'       # MFA route (requires prior session)
      auth.webauthn_login_route 'webauthn-login'     # Passwordless login route (no session required)
      auth.webauthn_remove_route 'webauthn-remove'

      # JSON API response configuration
      # In JSON mode, flash methods automatically become JSON responses
      auth.webauthn_setup_error_flash 'Error setting up biometric/security key'
      auth.webauthn_auth_error_flash 'Biometric/security key authentication failed'
      auth.webauthn_invalid_remove_param_message 'Invalid security key credential'
      auth.webauthn_invalid_auth_param_message 'Invalid authentication data'
      auth.webauthn_invalid_setup_param_message 'Invalid registration data'

      # NOTE: Passwordless WebAuthn login is enabled by default
      # Users can sign in with ONLY their biometric/security key
      # Autofill can be configured via webauthn_auth_js customization if needed
    end
  end
end
