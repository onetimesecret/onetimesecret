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
    # Endpoints reached programmatically by SP clients — no browser session,
    # no CSRF. /authorize is intentionally absent: it is browser-driven and
    # must keep CSRF protection. See the check_csrf? override below.
    OAUTH_NO_CSRF_PATHS = %w[/token /userinfo /revoke /jwks].freeze

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

        # The gem's *_url methods build `base_url + route_path(name)`, and
        # route_path uses rodauth's `prefix` (empty by default). Since this
        # rodauth instance is mounted under Auth::Application.uri_prefix
        # (`/auth`), the generated URLs come out without that prefix
        # (e.g. `http://host/authorize` instead of `http://host/auth/authorize`).
        #
        # Setting rodauth.prefix system-wide is the cleaner fix (issue #3104
        # follow-up — handoff item #12) but has broader fall-out: every URL
        # rodauth generates would change shape. For the discovery doc we just
        # need the endpoint URLs to be reachable, so we patch them here.
        define_method(:oauth_server_metadata_body) do |path = nil|
          body          = super(path)
          body[:issuer] = authorization_server_url

          prefix_oauth_endpoint_urls!(body)
          body
        end

        # OIDC discovery (`/.well-known/openid-configuration`) goes through
        # `openid_configuration_body`, which calls oauth_server_metadata_body
        # but then merges in `userinfo_endpoint: userinfo_url` AFTER our patch
        # (oidc.rb:811). Re-apply the prefix patch after super so userinfo
        # comes out with /auth.
        define_method(:openid_configuration_body) do |path = nil|
          body = super(path)
          prefix_oauth_endpoint_urls!(body)
          body
        end

        # Shared helper to rewrite endpoint URLs in a metadata body, adding
        # the Rack mount prefix when missing. rodauth-oauth builds URLs from
        # `base_url + route_path(name)` and route_path uses rodauth's own
        # `prefix` (empty by default); since the auth app is mounted under
        # /auth, the generated URLs need the prefix added.
        define_method(:prefix_oauth_endpoint_urls!) do |body|
          uri_prefix = Auth::Application.uri_prefix
          [:authorization_endpoint, :token_endpoint, :userinfo_endpoint, :jwks_uri, :revocation_endpoint, :registration_endpoint, :introspection_endpoint, :end_session_endpoint].each do |key|
            next unless body[key].is_a?(String)

            uri = URI.parse(body[key])
            # Treat as already-prefixed only when the path starts with
            # "/auth/" or equals "/auth" — guard against substring matches
            # (e.g. URI "/authorize" contains "/auth" but is NOT prefixed).
            next if uri.path == uri_prefix
            next if uri.path.start_with?("#{uri_prefix}/")

            uri.path  = "#{uri_prefix}#{uri.path}"
            body[key] = uri.to_s
          end
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

      # ─── CSRF bypass for IdP endpoints ─────────────────────────────────
      # rodauth-oauth's per-feature `check_csrf?` overrides compare against
      # *unprefixed* path names (e.g. `/token`), but rodauth's `request.path`
      # returns the full Rack `SCRIPT_NAME + PATH_INFO` (e.g. `/auth/token`)
      # — see oauth_base.rb:158. With rodauth's `prefix` left at the default
      # empty string but Auth::Router mounted at /auth, those comparisons
      # never match and the gem's intended CSRF exemption silently fails
      # back to super. (Underlying issue: rodauth prefix mismatch — see
      # issue #3104 follow-up item #12.)
      #
      # Endpoints in OAUTH_NO_CSRF_PATHS (defined above) are reached
      # programmatically by SP clients without a browser session, so CSRF
      # doesn't apply. PKCE + client_secret on /token + bearer auth on
      # /userinfo provide the protocol-level equivalents. /authorize is *not*
      # in this set — it is browser-driven and must keep CSRF protection
      # (matches gem behavior in non-JSON mode).
      auth.auth_class_eval do
        define_method(:check_csrf?) do
          paths      = Auth::Config::Features::OAuth::OAUTH_NO_CSRF_PATHS
          full_paths = paths.map { |p| "#{Auth::Application.uri_prefix}#{p}" }
          return false if full_paths.include?(request.path)
          return false if request.path.start_with?("#{Auth::Application.uri_prefix}/.well-known/")

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
      end
      private_key = OpenSSL::PKey::RSA.new(private_pem)
      auth.oauth_jwt_keys('RS256' => private_key)
      auth.oauth_jwt_public_keys('RS256' => private_key.public_key)
    end
  end
end
