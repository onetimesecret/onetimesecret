# lib/onetime/middleware/assume_https.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # AssumeHttps - Normalizes the request scheme to HTTPS behind a
    # TLS-terminating proxy that does NOT forward X-Forwarded-Proto.
    #
    # ## Why this exists
    #
    # Most reverse proxies (nginx, Caddy, AWS ALB) forward the original
    # client scheme via `X-Forwarded-Proto: https`, which Rack honors
    # natively, so `request.ssl?` is already true and this middleware is
    # never needed. Some tunneling proxies do NOT set that header: notably
    # Cloudflare Tunnel (cloudflared), which terminates TLS at Cloudflare's
    # edge and connects to the origin over plain HTTP without forwarding the
    # scheme. The origin then treats every request as HTTP, which suppresses
    # the Secure session cookie and breaks scheme-aware redirects/HSTS
    # (issue #3837, root cause of #3831).
    #
    # When `site.network.assume_https` is enabled, this middleware marks the
    # request as HTTPS so every downstream consumer (session cookie Secure
    # flag, the mounted auth app's HttpOrigin check, CSRF, HSTS, and scheme
    # redirects) sees one consistent scheme.
    #
    # ## UPGRADE-ONLY invariant
    #
    # This middleware ONLY upgrades http -> https. It never downgrades the
    # scheme and never strips or rewrites forwarded headers. When enabled,
    # it pins HTTPS in the server-side env even if Rack already resolves a
    # forwarded HTTPS scheme: downstream proxy-trust filtering may remove
    # that carrier, but must not undo the operator's HTTPS policy.
    # When the flag is off it is a strict no-op for every request, so native
    # Rack X-Forwarded-Proto handling for existing nginx/Caddy/ALB
    # deployments is completely unaffected.
    #
    # Mount FIRST in the stack so the normalized scheme is visible to every
    # downstream middleware and the mounted auth app.
    #
    # @note Only enable when a real TLS-terminating proxy fronts the origin.
    #   Enabling it on a directly-reachable origin would let a plain-HTTP
    #   client be treated as HTTPS.
    class AssumeHttps
      def initialize(app)
        @app     = app
        @enabled = OT.conf.dig('site', 'network', 'assume_https') == true
      end

      def call(env)
        return @app.call(env) unless @enabled

        # Do not depend on a forwarded scheme carrier surviving trust filtering.
        env['HTTPS']           = 'on'
        env['rack.url_scheme'] = 'https'

        @app.call(env)
      end
    end
  end
end
