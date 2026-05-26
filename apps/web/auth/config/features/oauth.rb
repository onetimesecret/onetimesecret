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

      # ─── Issuer / authorization server URL ────────────────────────────
      # The OP is mounted at base_url + Auth::Application.uri_prefix
      # (e.g. http://localhost:3000/auth). The gem's default
      # `authorization_server_url` returns just `base_url`, missing the
      # mount prefix — that would make ID tokens claim `iss:
      # http://localhost:3000` while OmniAuth/discovery clients expect
      # `http://localhost:3000/auth`.
      #
      # We override `authorization_server_url` (consumed by the default
      # `oauth_jwt_issuer`, oauth_jwt_base.rb:36) AND
      # `oauth_server_metadata_body` so the discovery `issuer` field
      # honors the same value — by default that field is `base_url`
      # ignoring authorization_server_url (oauth_base.rb:746-748).
      #
      # OAUTH_ISSUER overrides both for static prod deployments.
      auth.auth_class_eval do
        define_method(:authorization_server_url) do
          ENV.fetch('OAUTH_ISSUER') { "#{base_url}#{Auth::Application.uri_prefix}" }
        end

        define_method(:oauth_server_metadata_body) do |path = nil|
          body          = super(path)
          body[:issuer] = authorization_server_url
          body
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
      # `http` is allowed by default so localhost callbacks work in dev. In
      # production, tighten by setting OAUTH_VALID_URI_SCHEMES=https (a
      # space-separated list); when unset, both http and https are accepted.
      auth.oauth_valid_uri_schemes ENV.fetch('OAUTH_VALID_URI_SCHEMES', 'http https').split

      # ─── Token endpoint auth methods ───────────────────────────────────
      # No `client_secret_jwt` or `private_key_jwt` for v1.
      auth.oauth_token_endpoint_auth_methods_supported %w[client_secret_basic client_secret_post]

      # ─── Response types ────────────────────────────────────────────────
      # Enabling :oidc transitively pulls in :oauth_implicit_grant. We want
      # "code" only — no implicit or hybrid flows in v1.
      #
      # The setter below changes what is advertised in discovery metadata.
      # Note: this advertises `response_types_supported: ["code"]` which is
      # narrower than OIDC Discovery 1.0 §3 requires for a Dynamic OP (which
      # must list `code id_token` and `token id_token`). This is intentional
      # — we are the only consumer of our own IdP. Strict third-party clients
      # may refuse this discovery doc; that's by design for v1.
      auth.oauth_response_types_supported %w[code]

      # The setter alone does NOT block implicit/hybrid at /authorize. Request
      # validation routes through `check_valid_response_type?`, whose default
      # chain hardcodes acceptance of "token" (oauth_implicit_grant.rb:89-93)
      # and "id_token", "code id_token", "code token", "id_token token",
      # "code id_token token", "none" (oidc.rb:695-703). To actually reject
      # those response types, we have to override the predicate itself.
      auth.auth_class_eval do
        define_method(:check_valid_response_type?) do
          oauth_response_types_supported.include?(param_or_nil('response_type'))
        end
      end

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
