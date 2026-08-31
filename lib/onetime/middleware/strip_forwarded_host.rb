# lib/onetime/middleware/strip_forwarded_host.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # StripForwardedHost — remove client-settable forwarded-authority headers
    # from the Rack env so `Rack::Request#host` can never carry a host the
    # client chose (finding G-01, defense in depth).
    #
    # ## Why this exists
    #
    # Rack 3.2's `Rack::Request#host` resolves through `forwarded_authority`
    # FIRST: it honors `X-Forwarded-Host` and RFC 7239 `Forwarded` from ANY
    # client, with no proxy-trust gate. Rodauth's stock `base_url` (and any
    # other code reading `request.host`) would therefore build an auth URL on
    # a host the client forged — reset-link poisoning, one click from account
    # takeover on the multi-tenant platform.
    #
    # The primary fix lives in Auth::PublicHost / the base_url override, which
    # allowlist the host to a registered tenant and otherwise fall back to the
    # CANONICAL host, never `request.host`. This middleware is the belt to that
    # brace: with the forwarded-host headers gone, even a direct
    # `request.host` read (a future consumer, a gem) resolves to the `Host:`
    # authority the edge actually received — never a client-supplied one —
    # regardless of the operator's proxy configuration.
    #
    # ## Ordering — AFTER Rack::DetectHost, before anything reads request.host
    #
    # DetectHost has its OWN trust logic: it honors a forwarded host ONLY from
    # trusted infrastructure and publishes the result into
    # env[Rack::DetectHost.result_field_name] (which DomainStrategy then
    # classifies). That legitimate resolution — the whole custom-domain-behind-
    # a-proxy topology — MUST keep working, so this middleware runs immediately
    # AFTER DetectHost, once it has already consumed the headers. Nothing
    # between DetectHost and here reads `Rack::Request#host` (Admin isolation,
    # HttpOrigin and friends read the resolved env keys, not the raw
    # authority), and the mounted apps run later still, so by the time any
    # `request.host` read happens the forwarded headers are gone. DetectHost's
    # trust logic is left entirely intact — this only deletes what it has
    # already used.
    class StripForwardedHost
      # The two Rack env keys `Rack::Request#forwarded_authority` consults.
      FORWARDED_HOST_KEYS = %w[HTTP_X_FORWARDED_HOST HTTP_FORWARDED].freeze

      def initialize(app)
        @app = app
      end

      def call(env)
        FORWARDED_HOST_KEYS.each { |key| env.delete(key) }
        @app.call(env)
      end
    end
  end
end
