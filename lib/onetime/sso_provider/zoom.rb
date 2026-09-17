# lib/onetime/sso_provider/zoom.rb
#
# frozen_string_literal: true

# Zoom OAuth2 provider definition (issuerless — platform SSO only; see the
# registry header in lib/onetime/sso_provider/registry.rb).
#
# Plain OAuth2: no id_token, no JWT, no issuer concept anywhere in the
# strategy. resolve_issuer falls through to the '' sentinel, so
# refuse_issuerless_on_tenant? rejects this route on the tenant surface and it
# remains available for platform SSO only. That is the intended shape, not a
# gap to close.
#
# GEM/STRATEGY NAME MISMATCH — deliberate, do not "fix" either half:
#   gem_require: 'omniauth-zoom-v2'   the gem's entry file
#   strategy:    :zoom                OmniAuth::Strategies::Zoom's option :name
# cadenza-tech/omniauth-zoom-v2 is a maintained replacement for the abandoned
# omniauth-zoom; only the DISTRIBUTION carries the -v2 suffix. Requiring
# 'omniauth-zoom' or registering :zoom_v2 both fail.
#
# UID is Zoom's opaque user id from GET /v2/users/me, stable per Zoom account.
#
# TRUST NOTE: Zoom emails are verified by Zoom for accounts created through
# Zoom's own signup, but a Zoom account may belong to any managed domain a
# Zoom customer controls. Keep ZOOM_TRUST_EMAIL_FOR_LINKING false unless the
# deployment's users all sit inside one governed Zoom tenant.

module Onetime
  module SsoProvider
    module Zoom
      # Zoom's granular scope for the /v2/users/me read the strategy's
      # raw_info (and therefore info.email) depends on. Space-delimited; the
      # gem sets no default scope of its own.
      SCOPE = 'user:read:user'

      DEFINITION = {
        key: :zoom,
        label: 'Zoom',
        strategy: :zoom,
        gem_require: 'omniauth-zoom-v2',
        issuer_capable: false,
        required_vars: %w[ZOOM_CLIENT_ID ZOOM_CLIENT_SECRET],
        route_var: 'ZOOM_ROUTE_NAME',
        route_default: 'zoom',
        display_var: 'ZOOM_DISPLAY_NAME',
        display_default: 'Zoom',
        trust_var: 'ZOOM_TRUST_EMAIL_FOR_LINKING',
        trust_default: false,
        idp_origin: 'https://zoom.us',
        placeholder_options: {
          client_id: 'placeholder',
          client_secret: 'placeholder',
          scope: SCOPE,
        }.freeze,
        strategy_options: -> {
          {
            client_id: ENV.fetch('ZOOM_CLIENT_ID', nil),
            client_secret: ENV.fetch('ZOOM_CLIENT_SECRET', nil),
            scope: SCOPE,
          }
        },
      }.freeze
    end
  end
end
