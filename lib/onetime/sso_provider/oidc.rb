# lib/onetime/sso_provider/oidc.rb
#
# frozen_string_literal: true

# Generic OIDC provider definition. Field reference and the issuer-scoping
# background live in the registry header (lib/onetime/sso_provider/registry.rb).

module Onetime
  module SsoProvider
    module Oidc
      DEFINITION = {
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
      }.freeze
    end
  end
end
