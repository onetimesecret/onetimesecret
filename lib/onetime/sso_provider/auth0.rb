# lib/onetime/sso_provider/auth0.rb
#
# frozen_string_literal: true

# Auth0 provider definition. Field reference and the issuer-scoping background
# live in the registry header (lib/onetime/sso_provider/registry.rb).
#
# ISSUER-CAPABLE, but on a different footing than OIDC or Entra: the issuer we
# key identities on is the OPERATOR-PINNED AUTH0_DOMAIN, not a claim read out
# of the token. resolve_issuer precedence #1 returns options[:issuer], set
# below, and the identity row is ('auth0', 'https://<tenant>/', sub).
#
# WHY PINNED RATHER THAN CLAIM-READ (verified against omniauth-auth0 3.2.0):
# the gem's own claim validation — verify_iss, verify_aud, verify_nonce,
# verify_expiration — is gated on the authorize scope containing 'openid':
#
#   auth_scope = session_authorize_params[:scope]        # SYMBOL key
#   if auth_scope.respond_to?(:include?) && auth_scope.include?('openid')
#     jwt_validator.verify(credentials['id_token'], session_authorize_params)
#
# but session_authorize_params was written as `params.to_hash` on a
# Hashie::Mash, which produces STRING keys. `[:scope]` is therefore always
# nil, the gate is always false, and verify never runs. This is an upstream
# defect, not a configuration mistake — no scope value can open that gate.
#
# What DOES still hold, and what the identity key rests on:
#
#   - The id_token is fetched from the tenant's own token endpoint over TLS.
#   - extra.raw_info decodes it through JWTValidator#decode, which calls
#     JWT.decode(jwt, key, true, ...) — signature verification ON — against
#     the RS256 key from https://<AUTH0_DOMAIN>/.well-known/jwks.json (or the
#     client secret for HS256). Only the claim checks are disabled there.
#
# So `sub`, and therefore the uid, is cryptographically attested by the
# configured tenant's keys, and the issuer half of the key is a constant this
# deployment chose. A forged or foreign token cannot produce a row. Pinning
# the issuer is in fact the stronger arrangement here: it cannot be moved by
# anything in the token.
#
# CONSEQUENCE TO KNOW: with verify skipped, the gem also does not check the
# id_token's `exp` or the `nonce` it generated. Replay protection on this
# route rests on OmniAuth's `state` parameter (see the CSRF note in
# apps/web/auth/config/hooks/omniauth.rb) and on the authorization code being
# single-use at Auth0. If a future gem release fixes the key mismatch, the
# issuer set below is already the exact string verify_iss compares against, so
# validation starts working with no change here.
#
# TRAILING SLASH IS LOAD-BEARING. Auth0 issues tokens with
# `iss = https://<tenant>/`, and JWTValidator#uri_string normalizes its
# expected issuer to that same trailing-slash form. issuer_value below
# reproduces it exactly, so the pinned key matches the claim Auth0 actually
# asserts — and will match verify_iss if the gate is ever repaired.
#
# AUTH0_DOMAIN TAKES A FULL URL, scheme included
# (https://your-tenant.us.auth0.com), matching this app's OIDC_ISSUER
# convention rather than Auth0's own bare-hostname examples. The gem accepts
# either — domain_url prepends https:// when the scheme is missing — but
# AuthConfig#origin_from_url, which derives the CSP form-action origin from
# :idp_origin_from, returns nil for a schemeless value. A bare hostname would
# therefore authenticate fine while silently omitting the IdP from
# form-action, breaking the redirect under CSP. Requiring the scheme keeps the
# one env var honest for both consumers.
#
# WORTH KNOWING: Auth0 is itself an identity BROKER, so one tenant can
# federate many upstream IdPs behind a single issuer. Every upstream user
# collapses into the same (provider, issuer, uid) namespace, scoped by Auth0's
# `sub`. That is sound — Auth0 owns uniqueness of `sub` within its tenant —
# but it means AUTH0_TRUST_EMAIL_FOR_LINKING trusts EVERY connection the
# tenant has enabled, including any unverified database or social connection.
# Leave it false unless the tenant's connections are all verified-email IdPs
# inside your trust boundary.

module Onetime
  module SsoProvider
    module Auth0
      # Space-delimited. `openid` is what makes Auth0 return an id_token at
      # all, which is where the uid (`sub`) comes from — keep it first.
      SCOPE = 'openid profile email'

      # The issuer string Auth0 asserts, derived from the tenant domain:
      # scheme + host with exactly one trailing slash.
      #
      # FAILS LOUDLY on a schemeless value rather than quietly accepting it.
      # omniauth-auth0 would happily normalize `tenant.us.auth0.com` and sign
      # users in, but AuthConfig#origin_from_url — which builds the CSP
      # form-action origin from :idp_origin_from — rejects anything without an
      # http(s) scheme and returns nil. The result would be an SSO route that
      # works in every test that does not render CSP and breaks in every real
      # browser. A bare hostname is Auth0's OWN documented format, so operators
      # will reach for it; it has to be rejected where the message can name the
      # variable.
      #
      # THE RAISE IS CAUGHT, and deliberately so: configure_provider rescues it,
      # logs, and skips this one provider (see features/omniauth.rb). It must
      # never escape — that code runs inside Rodauth configuration, where an
      # exception takes down the entire auth app and every other
      # authentication method with it. Loud diagnosis, bounded blast radius.
      #
      # @param domain [String, nil] AUTH0_DOMAIN value
      # @return [String, nil] issuer with a trailing slash, or nil when unset
      # @raise [ArgumentError] when the value carries no http(s) scheme
      def self.issuer_value(domain)
        normalized = domain.to_s.strip
        return nil if normalized.empty?

        unless normalized.match?(%r{\Ahttps?://}i)
          raise ArgumentError,
            'AUTH0_DOMAIN must be a full URL including the scheme ' \
            "(e.g. https://#{normalized.chomp('/')}), not a bare hostname — " \
            'the CSP form-action origin is derived from it'
        end

        "#{normalized.chomp('/')}/"
      end

      # Is AUTH0_DOMAIN not just SET but USABLE?
      #
      # required_vars is a presence check, and presence is not enough here: a
      # schemeless AUTH0_DOMAIN is present, so it passes that gate, yet
      # configure_provider then rescues issuer_value's raise and registers no
      # route. Without this predicate the serializer would advertise an Auth0
      # button on the login and invite pages pointing at an /auth/sso/auth0
      # action that does not exist. AuthConfig#provider_active? consults it, so
      # the advertised set and the registered set cannot disagree.
      #
      # Auth0 is the only definition that needs one, because it is the only
      # one whose strategy_options can raise. A malformed OIDC_ISSUER still
      # registers a route and fails at the IdP instead, which is a different
      # failure with a different remedy.
      #
      # @return [Boolean]
      def self.domain_usable?
        !issuer_value(ENV.fetch('AUTH0_DOMAIN', nil)).nil?
      rescue ArgumentError
        false
      end

      DEFINITION = {
        key: :auth0,
        label: 'Auth0',
        strategy: :auth0,
        gem_require: 'omniauth-auth0',
        issuer_capable: true,
        required_vars: %w[AUTH0_CLIENT_ID AUTH0_CLIENT_SECRET AUTH0_DOMAIN],
        vars_valid: -> { domain_usable? },
        route_var: 'AUTH0_ROUTE_NAME',
        route_default: 'auth0',
        display_var: 'AUTH0_DISPLAY_NAME',
        display_default: 'Auth0',
        trust_var: 'AUTH0_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin_from: 'AUTH0_DOMAIN',
        # Auth0 is a PLATFORM provider: it is absent from
        # SsoConfig::PROVIDER_ROUTE_MAP, so tenant SSO never routes here and
        # these placeholders only ever satisfy the boot-time registration
        # orgs_sso_enabled? forces. The placeholder issuer is a reserved-TLD
        # host that can never be a real Auth0 tenant, mirroring oidc.rb.
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          domain: 'https://placeholder.invalid',
          issuer: 'https://placeholder.invalid/',
          authorize_params: { scope: SCOPE }.freeze,
        }.freeze,
        strategy_options: -> {
          domain = ENV.fetch('AUTH0_DOMAIN', nil)

          {
            client_id: ENV.fetch('AUTH0_CLIENT_ID', nil),
            client_secret: ENV.fetch('AUTH0_CLIENT_SECRET', nil),
            domain: domain,
            issuer: issuer_value(domain),
            # omniauth-auth0 builds the /authorize query from
            # options.authorize_params; a top-level :scope key is not read.
            authorize_params: { scope: SCOPE },
          }
        },
      }.freeze
    end
  end
end
