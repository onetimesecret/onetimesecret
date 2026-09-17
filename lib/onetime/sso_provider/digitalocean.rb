# lib/onetime/sso_provider/digitalocean.rb
#
# frozen_string_literal: true

# DigitalOcean OAuth2 provider definition (issuerless — platform SSO only; see
# the registry header in lib/onetime/sso_provider/registry.rb).
#
# Plain OAuth2: no id_token, no issuer concept. resolve_issuer falls through
# to the '' sentinel, so refuse_issuerless_on_tenant? rejects this route on the
# tenant surface and it remains available for platform SSO only.
#
# UID AND INFO COME FROM THE TOKEN RESPONSE BODY, not a userinfo call:
# OmniAuth::Strategies::Digitalocean reads uid from
# access_token.params['info']['uuid'] and builds info from that same nested
# hash (uuid, name, email, team_uuid, team_name). DigitalOcean returning a
# token without the non-standard `info` member would raise rather than degrade,
# so a strategy-level failure here surfaces as an SSO error rather than a
# mis-keyed identity — which is the safe direction.
#
# SCOPE: 'read' is deliberate and sufficient. The strategy's uid and email come
# from the token response, not from the account API, so no write grant is
# needed to sign a user in; asking for 'read write' would request control of
# the user's entire DigitalOcean account for no benefit. The scope string is
# SPACE-delimited — the gem's README calls this out explicitly because a comma
# is silently accepted and then mis-parsed by DigitalOcean.
#
# TEST-MODE ORIGIN SWITCH: when OmniAuth.config.test_mode is true the strategy
# hard-codes http://localhost:3000 as its site/authorize/token URLs. The
# :idp_origin below is the production origin, so a test-mode run would drive
# the browser to an origin the CSP form-action allowlist does not carry. This
# app's SSO specs drive the callback directly rather than following a redirect
# to the IdP, so nothing depends on it today — but a future browser-level SSO
# test against this provider has to account for it.
#
# TRUST NOTE: keep DIGITALOCEAN_TRUST_EMAIL_FOR_LINKING false. A DigitalOcean
# account's email is not re-verified per authorization, and team-scoped
# authorizations return the team's context alongside the user's.

module Onetime
  module SsoProvider
    module Digitalocean
      # Space-delimited, NOT comma-delimited. See the header note.
      SCOPE = 'read'

      DEFINITION = {
        key: :digitalocean,
        label: 'DigitalOcean',
        strategy: :digitalocean,
        gem_require: 'omniauth-digitalocean',
        issuer_capable: false,
        required_vars: %w[DIGITALOCEAN_CLIENT_ID DIGITALOCEAN_CLIENT_SECRET],
        route_var: 'DIGITALOCEAN_ROUTE_NAME',
        route_default: 'digitalocean',
        display_var: 'DIGITALOCEAN_DISPLAY_NAME',
        display_default: 'DigitalOcean',
        trust_var: 'DIGITALOCEAN_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: 'https://cloud.digitalocean.com',
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          scope: SCOPE,
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('DIGITALOCEAN_CLIENT_ID', nil),
            client_secret: ENV.fetch('DIGITALOCEAN_CLIENT_SECRET', nil),
            scope: SCOPE,
          }
        },
      }.freeze
    end
  end
end
