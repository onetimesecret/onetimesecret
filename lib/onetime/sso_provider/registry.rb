# lib/onetime/sso_provider/registry.rb
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
# Each provider's definition lives in its own file alongside this one
# (lib/onetime/sso_provider/<key>.rb) as Onetime::SsoProvider::<Key>::DEFINITION.
# This registry requires them and fixes their order — DEFINITIONS order is the
# default login-button order (see SSO_PROVIDER_ORDER in .env.reference).
#
# ADDING A PROVIDER is a Gemfile line plus one definition file here (plus
# brand polish in the frontend if desired). See
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
#                     boot-registration time, so these files stay loadable in
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
#   idp_origin / idp_origin_from: feed the CSP form-action derivations — the
#                     boot-time AuthConfig#sso_form_action_origins (platform
#                     providers) and, for entra's static origin, the
#                     per-request AuthConfig#tenant_idp_origin (tenant SSO,
#                     #4173). Either a static origin for providers whose IdP
#                     host is fixed, or the name of an env var whose URL the
#                     origin is derived from (OIDC's issuer; tenant OIDC uses
#                     the SsoConfig record's issuer instead). ENTRA is static
#                     because the OmniAuth strategy hard-pins the commercial
#                     cloud (login.microsoftonline.com); there is no
#                     sovereign-cloud authority env in this app. For a
#                     PLATFORM provider pointed at a sovereign endpoint,
#                     SSO_FORM_ACTION_ORIGINS is the override. Do NOT reach
#                     for it for TENANT entra: a tenant config passes no
#                     authority option and has no authority field, so it
#                     always redirects to the commercial cloud — the override
#                     would widen form-action on every page for every tenant
#                     while fixing nothing. Sovereign tenants configure
#                     provider type oidc with the sovereign issuer instead
#                     (docs/authentication/per-install-sso.md).
#                     CONSTRAINT on adding a second non-OIDC TENANT provider:
#                     AuthConfig#tenant_idp_origin picks the definition by the
#                     SsoConfig::PROVIDER_ROUTE_MAP :default route name and
#                     never consults that entry's :env_var override, so an
#                     operator-renamed route resolves the DEFAULT definition,
#                     silently. Harmless for every provider that exists today:
#                     the non-OIDC tenant type (entra_id) carries a STATIC
#                     idp_origin, so which route name the operator chose cannot
#                     change the answer (and tenant OIDC bypasses the registry
#                     entirely, deriving from the SsoConfig record's issuer).
#                     A new provider whose route-name override must also select
#                     a DIFFERENT definition — e.g. per-cloud definitions keyed
#                     off the route env — breaks that assumption and has to
#                     teach #tenant_idp_origin to resolve :env_var first.
#   placeholder_options: strategy options (minus name:) used when platform
#                     credentials are absent but org-level SSO is enabled —
#                     the OmniAuthTenant hook injects real tenant credentials
#                     at request time
#   strategy_options: zero-arg callable returning strategy options (minus
#                     name:) built from the env at boot. Called only after
#                     required_vars are verified present.

require_relative 'oidc'
require_relative 'entra'
require_relative 'google'
require_relative 'github'

module Onetime
  module SsoProvider
    module Registry
      DEFINITIONS = [
        Oidc::DEFINITION,
        Entra::DEFINITION,
        Google::DEFINITION,
        Github::DEFINITION,
      ].freeze

      # Definition lookup by :key. Raises KeyError on an unknown key so a typo
      # fails loudly at boot rather than silently skipping a provider.
      def self.fetch(key)
        DEFINITIONS.find { |defn| defn[:key] == key } ||
          raise(KeyError, "unknown SSO provider definition: #{key.inspect}")
      end
    end
  end
end
