# lib/onetime/sso_provider/google.rb
#
# frozen_string_literal: true

# Google OAuth2 provider definition (issuerless — platform SSO only; see
# the registry header in lib/onetime/sso_provider/registry.rb).

module Onetime
  module SsoProvider
    module Google
      DEFINITION = {
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
      }.freeze
    end
  end
end
