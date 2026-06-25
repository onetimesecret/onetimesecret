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

      # ─── Mount prefix / issuer ─────────────────────────────────────────
      # The OP is mounted under Auth::Application.uri_prefix (e.g. /auth) via
      # Rack::URLMap, which sets SCRIPT_NAME=/auth and strips it from PATH_INFO.
      # Rodauth route matching keeps working off `remaining_path` (so `prefix`
      # is left at its empty default), but `base_url`/`route_path` don't include
      # the mount point — so discovery URLs, the `issuer`, and the per-endpoint
      # CSRF exemptions used to drop `/auth`.
      #
      # The forked rodauth-oauth exposes `oauth_mount_prefix` (Gemfile pins the
      # fork; see #3465 and apps/web/auth/docs/rodauth-prefix-mismatch.md). It
      # makes the gem honor the mount point in `*_path`/`*_url` generation, the
      # discovery `issuer` (via authorization_server_url), and the per-feature
      # `check_csrf?` comparisons — replacing the local
      # prefix_oauth_endpoint_urls! helper and the oauth_server_metadata_body /
      # openid_configuration_body / check_csrf? overrides this file used to
      # carry. Route matching is unaffected (it uses remaining_path), so setting
      # rodauth's global `prefix` is still not needed.
      # Block form (not a bare value): Auth::Application is not defined yet when
      # this config loads (application.rb requires config.rb before defining the
      # Application class), so the prefix must be resolved lazily at request
      # time, when oauth_mount_prefix is first read.
      auth.oauth_mount_prefix { Auth::Application.uri_prefix }

      # The gem derives the discovery `issuer` (and oauth_jwt_issuer,
      # oauth_jwt_base.rb:36) from authorization_server_url, whose default is now
      # `base_url + oauth_mount_prefix`. The only issuer behavior that stays
      # OTS-specific is OAUTH_ISSUER, which pins the issuer for static prod
      # deployments; fall back to the gem default otherwise.
      auth.auth_class_eval do
        define_method(:authorization_server_url) do
          ENV.fetch('OAUTH_ISSUER') { super() }
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
      # `offline_access` must be present here (the server-level allow-list) or
      # rodauth-oauth strips it from the request before the grant row is
      # written. With :oidc enabled, oidc.rb only issues a refresh_token when
      # `offline_access` survives into the granted scopes, so dropping it here
      # silently breaks refresh tokens for every client (the SP in omniauth.rb
      # requests it). The seeded SP's per-application `scopes` column must list
      # it too — see seed_dev_oauth_client.rb.
      auth.oauth_application_scopes %w[openid profile email offline_access]

      # ─── PKCE enforcement ──────────────────────────────────────────────
      # :oauth_pkce (enabled above) makes PKCE *available* but not *mandatory*:
      # without this, a client can complete the authorization-code flow with no
      # code_challenge at all. Migration 010's CHECK constraint only rejects a
      # stored code_challenge_method='plain' — it does NOT force PKCE to be
      # present. oauth_require_pkce closes that gap so the "PKCE-only" posture is
      # enforced server-side for every registered client, not just the seeded SP.
      # Every authorization-code flow in this codebase already uses S256 PKCE
      # (omniauth.rb sets `pkce: true`), so this rejects no working client.
      auth.oauth_require_pkce true

      # ─── URI schemes ───────────────────────────────────────────────────
      # Production defaults to https-only: an http:// redirect is interceptable,
      # letting an attacker steal the authorization code before PKCE verification,
      # so an operator who flips AUTH_OAUTH_ENABLED=true without reading the env
      # docs must not silently accept http:// redirect URIs. dev/test default to
      # `http https` so localhost callbacks keep working (the seeded SP client
      # registers http://localhost:3000/...). OAUTH_VALID_URI_SCHEMES (a
      # space-separated list) overrides the default in any environment — set it
      # to `http https` to allow http in a non-prod-tagged deployment.
      default_uri_schemes = Onetime.production? ? 'https' : 'http https'
      auth.oauth_valid_uri_schemes ENV.fetch('OAUTH_VALID_URI_SCHEMES', default_uri_schemes).split

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

      # ─── CSRF: keep /revoke exempt (load-bearing, OTS-specific) ─────────
      # Now that oauth_mount_prefix aligns the gem's `*_path` helpers with the
      # browser-absolute `request.path`, the gem's own per-feature `check_csrf?`
      # exemptions work again: /token (oauth_base) and /userinfo (oidc) are
      # exempt at the gem level, /authorize keeps CSRF (browser-driven), and
      # /jwks is GET-only. So the broad local request.path override is gone.
      #
      # The one exemption the gem does NOT give us is a blanket /revoke: its
      # oauth_token_revocation `check_csrf?` enforces CSRF on form-encoded
      # /revoke (exempting only JSON), which is inverted from RFC 7009 —
      # /revoke is form-encoded and authenticated by client credentials, not
      # CSRF tokens. SP clients call it programmatically, so we exempt it
      # regardless of content type. This is independent of the prefix fix; do
      # NOT drop it. (revoke_path is mount-aware via oauth_mount_prefix, so this
      # matches request.path under the /auth mount.)
      auth.auth_class_eval do
        define_method(:check_csrf?) do
          return false if request.path == revoke_path

          super()
        end
      end

      # ─── ID-token: omit auth_time when sessionless ────────────────────
      # FIX (#3233): rodauth-oauth's id_token_claims (oidc.rb:567) writes
      # `claims[:auth_time] = get_oidc_account_last_login_at(account_id).to_i`
      # unconditionally. The default `get_oidc_account_last_login_at`
      # (oidc.rb:352) queries `active_sessions` and returns nil when the
      # account has no active session — and `nil.to_i == 0`. The gem then
      # emits `auth_time: 0` in the ID token, which OIDC Core 1.0 §2 does
      # not permit: `auth_time` is "Time when the End-User authentication
      # occurred"; absent that signal, the claim should be omitted entirely.
      # Emitting 0 (epoch) misrepresents the authentication moment as
      # 1970-01-01T00:00:00Z.
      #
      # We call super and drop `:auth_time` when it serializes to 0,
      # leaving the rest of the gem's claims (sub, aud, iat, exp, iss,
      # nonce, acr, at_hash, c_hash) intact. A non-zero auth_time from
      # an active session passes through unchanged.
      auth.auth_class_eval do
        define_method(:id_token_claims) do |oauth_grant, signing_algorithm|
          claims = super(oauth_grant, signing_algorithm)
          claims.delete(:auth_time) if claims[:auth_time].to_i.zero?
          claims
        end
      end

      # ─── Grant types ───────────────────────────────────────────────────
      # No client_credentials, device_code, password, or assertion grants in v1.
      auth.oauth_grant_types_supported %w[authorization_code refresh_token]

      # ─── /userinfo JWT exp enforcement — defense-in-depth gap ─────────
      # FINDING (#3231): rodauth-oauth's json-jwt branch
      # (oauth_jwt_base.rb:217-285) is the active code path here because both
      # json-jwt and ruby-jwt are loaded and `defined?(JSON::JWT)` wins at
      # gem load time (oauth_jwt_base.rb:132). Its post-decode claim
      # validation at lines 269-278 is an AND-chain:
      #
      #   if verify_claims &&
      #      (!claims[:exp] || Time.at(claims[:exp]) < now) &&
      #      claims[:nbf] && Time.at(claims[:nbf]) < now &&
      #      claims[:iat] && Time.at(claims[:iat]) < now &&
      #      verify_iss && claims[:iss] != oauth_jwt_issuer &&
      #      verify_aud && !verify_aud(claims[:aud], claims[:client_id]) &&
      #      verify_jti && !verify_jti(claims[:jti], claims)
      #     return
      #   end
      #
      # So the gem only rejects a JWT when EVERY claim check fails
      # simultaneously. A token with a valid iss/aud/iat/jti but a past `exp`
      # slips through the JWT-level gate. JSON::JWT.decode itself also does
      # not enforce `exp`.
      #
      # In practice /userinfo is protected by the DB-row gate:
      # `valid_oauth_grant_ds` (oauth_base.rb:596-602) filters
      # `oauth_grants.expires_in >= CURRENT_TIMESTAMP`, and /token bumps
      # that column to `now + oauth_access_token_expires_in` (3600s) on every
      # exchange. The DB row's expiry is the effective expiry for issued
      # access tokens, and an attacker cannot forge a row.
      #
      # We do NOT override `jwt_decode` here. Patching the gem's predicate
      # safely requires re-implementing all six claim checks, which we'd
      # have to keep in sync with upstream on every gem bump. A correct fix
      # belongs upstream.
      #
      # Regression coverage that pins both halves of this:
      #   - spec/integration/oauth_idp_lifecycle_spec.rb:312
      #     'FINDING: does NOT enforce JWT exp at /userinfo' — documents the
      #     gem's current (broken) behavior. If this starts failing with 401,
      #     the gem fixed the AND-chain and the documentation here should be
      #     revisited.
      #   - spec/integration/oauth_idp_lifecycle_spec.rb:355
      #     'rejects /userinfo when the DB grant row is expired' — pins the
      #     DB-row gate we actually rely on.

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
      end.gsub('\n', "\n") # unescape the single-line .env form back into a
      # multi-line PEM (mirrors the gsub("\n", '\n') in bin/generate_oauth_keys);
      # a no-op for raw multi-line values from Docker/K8s secrets.
      private_key = OpenSSL::PKey::RSA.new(private_pem)
      auth.oauth_jwt_keys('RS256' => private_key)
      auth.oauth_jwt_public_keys('RS256' => private_key.public_key)
    end
  end
end
