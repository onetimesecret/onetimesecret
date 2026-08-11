# lib/onetime/sso_provider/github.rb
#
# frozen_string_literal: true

# GitHub OAuth2 provider definition (issuerless — platform SSO only; see
# the registry header in lib/onetime/sso_provider/registry.rb).

module Onetime
  module SsoProvider
    module Github
      DEFINITION = {
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
      }.freeze
    end
  end
end
