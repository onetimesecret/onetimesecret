# apps/web/auth/config/features/oauth.rb
#
# frozen_string_literal: true

#
# OAuth2/OIDC Identity Provider feature for OneTimeSecret.
# Turns this OTS instance into an authorization server (IdP). External
# clients can use the standard authorization-code + PKCE flow against
# this instance's /authorize, /token, /jwks, /userinfo endpoints.
#
# This is the inverse of the OmniAuth feature (apps/web/auth/config/features/omniauth.rb).
# OmniAuth makes OTS a *consumer* of external IdPs (SP role).
# This feature makes OTS *act as* an IdP (OP role).
#
# Gem: rodauth-oauth 1.6.x (https://gitlab.com/honeyryderchuck/rodauth-oauth).
#
# Issue: https://github.com/onetimesecret/onetimesecret/issues/3104
#
# Tables (created by migrations 008/009):
#   - oauth_applications  — registered clients
#   - oauth_grants        — auth codes, access tokens, refresh tokens (single row)
#
# Routes (auto-mounted by the rodauth-oauth features below):
#   - POST /token         — :oauth_base via :oauth_authorization_code_grant
#   - GET/POST /authorize — :oauth_authorize_base
#   - GET /jwks           — :oauth_jwt_jwks (pulled in by :oidc)
#   - GET/POST /userinfo  — :oidc
#   - POST /revoke        — :oauth_token_revocation
#
# Discovery routes (NOT auto-mounted; mounted in router.rb in task 4):
#   - GET /.well-known/openid-configuration
#   - GET /.well-known/oauth-authorization-server
#
# JWT signing keys: not provisioned here. See the comment in the configure
# block. Without keys, /token and OIDC ID-token issuance will fail at
# request time, but boot is unaffected.
#

require 'rodauth/oauth'

module Auth::Config::Features
  module OAuth
    def self.configure(auth)
      auth.enable :oauth_authorization_code_grant,
        :oauth_pkce,
        :oidc,
        :oauth_token_revocation

      # ─── Tables ─────────────────────────────────────────────────────────
      # Explicit even though these match the gem defaults. Keeps the wiring
      # to migrations 008/009 obvious to future readers.
      auth.oauth_applications_table :oauth_applications
      auth.oauth_grants_table :oauth_grants

      # ─── Issuer ─────────────────────────────────────────────────────────
      # Block form so the value is evaluated per-request, not at load time.
      # This lets the same boot serve multiple custom domains correctly
      # (e.g. dev-and-prod from one container with different HOST values).
      #
      # Resolution order:
      #   1. OAUTH_ISSUER env var (explicit override; usually for prod)
      #   2. site.host from etc/config.yaml (project-wide site identity)
      #   3. http://localhost:3000/auth (dev/test fallback)
      auth.oauth_jwt_issuer do
        ENV.fetch('OAUTH_ISSUER') do
          host = Onetime.conf.dig('site', 'host')
          host && !host.to_s.empty? ? "https://#{host}/auth" : 'http://localhost:3000/auth'
        end
      end

      # ─── Lifetimes ──────────────────────────────────────────────────────
      # `oauth_grant_expires_in` is the AUTH CODE TTL, not the access token
      # TTL (easy naming trap — see exploration notes).
      auth.oauth_grant_expires_in 300                        # 5 min  (gem default; explicit for clarity)
      auth.oauth_access_token_expires_in 3600                # 60 min (gem default; explicit for clarity)
      auth.oauth_refresh_token_expires_in 60 * 60 * 24 * 30  # 30 days; tighter than gem's 1-year default

      # ─── Refresh token rotation ────────────────────────────────────────
      # Issue a new refresh token on each use; the old one is invalidated.
      # "rotation" matches the gem default; making it explicit so a future
      # reader sees the security posture without having to look it up.
      auth.oauth_refresh_token_protection_policy 'rotation'

      # ─── Scopes ────────────────────────────────────────────────────────
      auth.oauth_application_scopes %w[openid profile email]

      # ─── URI schemes ───────────────────────────────────────────────────
      # `http` is allowed so localhost callbacks work in dev. In production
      # this list should be tightened to %w[https] only; do so by setting
      # OAUTH_VALID_URI_SCHEMES or via a deploy-time override in this
      # feature module.
      auth.oauth_valid_uri_schemes %w[http https]

      # ─── Token endpoint auth methods ───────────────────────────────────
      # No `client_secret_jwt` or `private_key_jwt` for v1.
      auth.oauth_token_endpoint_auth_methods_supported %w[client_secret_basic client_secret_post]

      # ─── Response types ────────────────────────────────────────────────
      # Even though enabling :oidc transitively pulls in :oauth_implicit_grant,
      # we restrict the advertised + accepted response_types to "code" only.
      # This makes implicit + hybrid flows unavailable at the protocol level,
      # which is the v1 security stance.
      auth.oauth_response_types_supported %w[code]

      # ─── Grant types ───────────────────────────────────────────────────
      # No client_credentials, device_code, password, or assertion grants in v1.
      auth.oauth_grant_types_supported %w[authorization_code refresh_token]

      # ─── JWT signing keys ──────────────────────────────────────────────
      #
      # RSA keypair for signing OIDC ID tokens and JWT access tokens.
      # The same PEM must be present on every boot — losing it invalidates
      # every live ID token and JWT access token issued under it.
      #
      # Storage strategy: env var carrying the PEM directly. Matches the
      # precedent of AUTH_SECRET (apps/web/auth/config/base.rb:12) and
      # ARGON2_SECRET (lib/onetime/auth_config.rb:63) — both are independent
      # cryptographic material that lives in the environment, not in the
      # YAML defaults (etc/defaults/auth.defaults.yaml comments them as
      # "Category 2: random, NOT derived from SECRET").
      #
      # Generation:
      #   $ bin/generate_oauth_keys     # prints PEM + .env snippet
      # or:
      #   $ openssl genrsa 2048
      #
      # The public key is derived from the private key — no separate env
      # var. JWKS exposes the public modulus + exponent.
      private_pem = ENV.fetch('OAUTH_JWT_RSA_PRIVATE_KEY') do
        raise 'OAUTH_JWT_RSA_PRIVATE_KEY must be set when AUTH_OAUTH_ENABLED=true. ' \
              'Generate with: bin/generate_oauth_keys (or `openssl genrsa 2048`).'
      end
      private_key = OpenSSL::PKey::RSA.new(private_pem)
      auth.oauth_jwt_keys('RS256' => private_key)
      auth.oauth_jwt_public_keys('RS256' => private_key.public_key)
    end
  end
end
