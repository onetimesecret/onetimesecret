# lib/onetime/sso_provider/entra.rb
#
# frozen_string_literal: true

# Microsoft Entra ID provider definition. Field reference and the
# issuer-scoping background live in the registry header
# (lib/onetime/sso_provider/registry.rb).
#
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

module Onetime
  module SsoProvider
    module Entra
      DEFINITION = {
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
      }.freeze
    end
  end
end
