# lib/onetime/sso_provider_registry.rb
#
# frozen_string_literal: true

# Single source of truth for SSO (OmniAuth) provider wiring.
#
# Every place that needs to know "which providers exist and how are they
# configured" reads from DEFINITIONS below:
#
#   - Onetime::AuthConfig#provider_definitions — serializer gating
#     (sso_providers), email-linking trust flags, and CSP form-action
#     origins.
#   - Auth::Config::Features::OmniAuth.configure — boot-time strategy
#     registration (real credentials or tenant-SSO placeholders).
#
# ADDING A PROVIDER is a Gemfile line plus one hash entry here (plus brand
# polish in the frontend if desired). See
# docs/authentication/adding-sso-providers.md for the full checklist —
# including the issuer-scoping decision each new provider forces:
#
#   ISSUER-CAPABLE (:issuer_capable true — OIDC, Entra, and other providers
#   whose auth hash carries a validated issuer) participate fully in the
#   (provider, issuer, uid) identity key and are usable on both the platform
#   and tenant surfaces.
#
#   ISSUERLESS (:issuer_capable false — plain OAuth2: GitHub, Google,
#   Facebook, Discord, ...) resolve to the '' sentinel issuer on every
#   surface, so the tenant surface REFUSES them at callback time
#   (refuse_issuerless_on_tenant? in features/omniauth.rb). They remain
#   available for platform SSO only. Prefer OIDC-capable providers when
#   expanding the roster.
#
# Field reference (per definition):
#
#   key:              stable internal identifier (Symbol)
#   label:            human label for boot logs ('OIDC', 'Entra ID', ...)
#   strategy:         OmniAuth strategy symbol passed to omniauth_provider
#   gem_require:      require path for the strategy gem (required lazily at
#                     boot-registration time, so this file stays loadable in
#                     environments without the omniauth gems)
#   issuer_capable:   whether the strategy yields a validated issuer (see above)
#   required_vars:    env vars that must ALL be present for the provider to
#                     register with real credentials (and to appear in
#                     sso_providers / CSP origins)
#   route_var/route_default:     env var and default for the route name — the
#                     URL segment, auth-hash provider value, and
#                     account_identities.provider value
#   display_var/display_default: env var and default for the button label
#   trust_var/trust_default:     the #3836 email-linking escape hatch — an
#                     explicit per-provider operator declaration that the IdP
#                     is inside the trust boundary (see
#                     AuthConfig#trust_email_for_linking?)
#   idp_origin / idp_origin_from: feed AuthConfig#sso_form_action_origins — a
#                     static origin for providers whose IdP host is fixed, or
#                     the name of an env var whose URL the origin is derived
#                     from (OIDC's issuer). ENTRA is static because the
#                     OmniAuth strategy hard-pins the commercial cloud
#                     (login.microsoftonline.com); there is no sovereign-cloud
#                     authority env in this app — use SSO_FORM_ACTION_ORIGINS
#                     for those.
#   placeholder_options: strategy options (minus name:) used when platform
#                     credentials are absent but org-level SSO is enabled —
#                     the OmniAuthTenant hook injects real tenant credentials
#                     at request time
#   strategy_options: zero-arg callable returning strategy options (minus
#                     name:) built from the env at boot. Called only after
#                     required_vars are verified present.
module Onetime
  module SsoProviderRegistry
    DEFINITIONS = [
      {
        key: :oidc,
        label: 'OIDC',
        strategy: :openid_connect,
        gem_require: 'omniauth_openid_connect',
        issuer_capable: true,
        # OIDC_CLIENT_SECRET is intentionally NOT required: PKCE flows may
        # run without one (see strategy_options).
        required_vars: %w[OIDC_ISSUER OIDC_CLIENT_ID],
        route_var: 'OIDC_ROUTE_NAME',
        route_default: 'oidc',
        display_var: 'OIDC_DISPLAY_NAME',
        # AuthConfig#provider_definitions overlays the operator's legacy
        # sso_display_name over this default at read time.
        display_default: 'SSO',
        trust_var: 'OIDC_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin_from: 'OIDC_ISSUER',
        placeholder_options: {
          scope: [:openid, :email, :profile],
          response_type: :code,
          issuer: 'https://placeholder.invalid',
          client_options: { identifier: 'placeholder' },
          discovery: true,
          pkce: true,
        }.freeze,
        strategy_options: -> {
          client_secret        = ENV.fetch('OIDC_CLIENT_SECRET', '')
          # redirect_uri is omitted here — the omniauth_setup hook injects it
          # at runtime from the request host (see omniauth_tenant.rb).
          client_opts          = { identifier: ENV.fetch('OIDC_CLIENT_ID', nil) }
          # Only include secret if provided (PKCE flows may not have one)
          client_opts[:secret] = client_secret unless client_secret.empty?

          {
            scope: [:openid, :email, :profile],
            response_type: :code,
            issuer: ENV.fetch('OIDC_ISSUER', nil),
            client_options: client_opts,
            discovery: true,
            pkce: true,
          }
        },
      },
      {
        # NOTE: The route name controls both the URL route segment AND the
        # provider value stored in account_identities.provider and returned in
        # the auth hash. Default 'entra' (without the name: override,
        # omniauth-entra-id would default to 'entra_id').
        #
        # SECURITY — dependency on issuer-scoping (#3840 Phase 0 / #3838
        # item 5): by default omniauth-entra-id composes the uid as `tid+oid`
        # (tenant id + object id), so it is unique across tenants on its own.
        # A deployer who sets `ignore_tid: true` degrades the uid to `oid`
        # ALONE — the same oid can then recur across tenants. Cross-tenant
        # safety in that config relies ENTIRELY on the (provider, issuer, uid)
        # key: resolve_issuer scopes the row by the validated `iss` claim (see
        # omniauth_token_issuer in features/omniauth.rb). If you add
        # `ignore_tid: true` to strategy_options, do NOT weaken that issuer
        # resolution.
        key: :entra,
        label: 'Entra ID',
        strategy: :entra_id,
        gem_require: 'omniauth-entra-id',
        issuer_capable: true,
        required_vars: %w[ENTRA_TENANT_ID ENTRA_CLIENT_ID ENTRA_CLIENT_SECRET],
        route_var: 'ENTRA_ROUTE_NAME',
        route_default: 'entra',
        display_var: 'ENTRA_DISPLAY_NAME',
        display_default: 'Microsoft',
        trust_var: 'ENTRA_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: 'https://login.microsoftonline.com',
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          tenant_id: 'placeholder',
          scope: 'openid profile email',
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('ENTRA_CLIENT_ID', nil),
            client_secret: ENV.fetch('ENTRA_CLIENT_SECRET', nil),
            tenant_id: ENV.fetch('ENTRA_TENANT_ID', nil),
            scope: 'openid profile email',
          }
        },
      },
      {
        key: :google,
        label: 'Google',
        strategy: :google_oauth2,
        gem_require: 'omniauth-google-oauth2',
        issuer_capable: false,
        required_vars: %w[GOOGLE_CLIENT_ID GOOGLE_CLIENT_SECRET],
        route_var: 'GOOGLE_ROUTE_NAME',
        route_default: 'google',
        display_var: 'GOOGLE_DISPLAY_NAME',
        display_default: 'Google',
        trust_var: 'GOOGLE_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: 'https://accounts.google.com',
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          scope: 'openid,email,profile',
          prompt: 'select_account',
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('GOOGLE_CLIENT_ID', nil),
            client_secret: ENV.fetch('GOOGLE_CLIENT_SECRET', nil),
            scope: 'openid,email,profile',
            prompt: 'select_account',
          }
        },
      },
      {
        key: :github,
        label: 'GitHub',
        strategy: :github,
        gem_require: 'omniauth-github',
        issuer_capable: false,
        required_vars: %w[GITHUB_CLIENT_ID GITHUB_CLIENT_SECRET],
        route_var: 'GITHUB_ROUTE_NAME',
        route_default: 'github',
        display_var: 'GITHUB_DISPLAY_NAME',
        display_default: 'GitHub',
        trust_var: 'GITHUB_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: 'https://github.com',
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          scope: 'user:email',
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('GITHUB_CLIENT_ID', nil),
            client_secret: ENV.fetch('GITHUB_CLIENT_SECRET', nil),
            scope: 'user:email',
          }
        },
      },
    ].map(&:freeze).freeze

    # Definition lookup by :key. Raises KeyError on an unknown key so a typo
    # fails loudly at boot rather than silently skipping a provider.
    def self.fetch(key)
      DEFINITIONS.find { |defn| defn[:key] == key } ||
        raise(KeyError, "unknown SSO provider definition: #{key.inspect}")
    end
  end
end
