# lib/onetime/middleware/http_origin_options.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    # Shared options for Rack::Protection::HttpOrigin.
    #
    # HttpOrigin resolves the request host via Rack::Request#host, which reads
    # the Host header (or X-Forwarded-Host when present). Behind a proxy tier
    # that rewrites Host to the canonical origin and forwards the true public
    # host in another header (Apx-Incoming-Host, X-Original-Host, Forwarded),
    # that answer is wrong — which is exactly why the app mounts
    # Rack::DetectHost and DomainStrategy, whose validated result is published
    # as env['onetime.display_domain'].
    #
    # Without this allow_if, every unsafe-method request from a custom domain
    # is rejected with 403 before reaching a route, because the Origin header
    # (custom domain) never byte-matches the Host header (canonical origin).
    #
    # The comparison here is exact and https-only, against a host that
    # DetectHost accepts from forwarded headers only behind trusted
    # infrastructure and DomainStrategy classifies against registered custom
    # domains. A forged Origin cannot match because an attacker cannot move
    # display_domain. An absent or empty display_domain fails closed: allow_if
    # returns false and HttpOrigin's own Origin-vs-Host check decides.
    #
    # Consumed by both HttpOrigin mounts — Onetime::Middleware::Security
    # (toggle: site.middleware.http_origin) and the auth app's middleware
    # profile (apps/web/auth/application.rb) — so their behavior cannot drift.
    module HttpOriginOptions
      # Accept an Origin that matches the host the application already
      # resolved for this request. The scheme is hardcoded https: custom
      # domains are only served over TLS, and a laxer scheme would let a
      # network attacker on a plaintext leg mint a matching Origin.
      ALLOW_IF = ->(env) do
        display = env['onetime.display_domain'].to_s
        next false if display.empty?

        env['HTTP_ORIGIN'].to_s == "https://#{display}"
      end

      def self.options
        { allow_if: ALLOW_IF }
      end
    end
  end
end
