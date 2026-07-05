# apps/web/core/middleware/request_setup.rb
#
# frozen_string_literal: true

require 'onetime/logger_methods'

# RequestSetup middleware handles request-level initialization for Web Core.
#
# Responsibilities:
# - Generate CSP nonce and make available to views via req.env['onetime.nonce']
# - Set default Content-Type if not already set
# - Initialize locale from request
#
# This middleware should run after session middleware but before authentication
# and error handling middleware.

module Core
  module Middleware
    class RequestSetup
      include Onetime::LoggerMethods

      def initialize(app, default_content_type: 'text/html; charset=utf-8')
        @app                  = app
        @default_content_type = default_content_type
      end

      def call(env)
        setup_request(env)
        status, headers, body = @app.call(env)
        finalize_response(status, headers, body, env)
      end

      private

    def setup_request(env)
      # Generate unique nonce for CSP headers (used by views)
      nonce                = SecureRandom.base64(16)
      env['onetime.nonce'] = nonce

      # Locale is handled by Otto::Locale::Middleware
      # Available via env['otto.locale']

      http_logger.debug 'Request setup complete', { nonce: nonce[0, 8] } if OT.debug?
    end

    def finalize_response(status, headers, body, env)
      ensure_content_type(headers)
      emit_csp_header(headers, env)

      [status, headers, body]
    end

    # Default the response Content-Type when a route left it unset.
    #
    # The presence check is deliberately case-insensitive. Rack 3 mandates
    # lowercase response-header keys and Core emits them throughout (see the
    # lowercase 'content-type' defaults in application.rb), so in practice the
    # key is already 'content-type'. But a stray capital-cased 'Content-Type'
    # from any layer must still count as "already set": a naive
    # `headers['content-type'] ||= ...` would miss it and write a *second*,
    # lowercase content-type key, leaving the response with two conflicting
    # content types — and, because Writer.apply below reads Content-Type
    # case-insensitively, that injected text/html default could then draw a CSP
    # onto what was really a non-HTML response. Matching any casing here closes
    # that gap regardless of who set the header, or how.
    def ensure_content_type(headers)
      return if headers.any? { |key, _value| key.to_s.casecmp?('content-type') }

      headers['content-type'] = @default_content_type
    end

    # Emit the Content-Security-Policy header for HTML responses.
    #
    # Emission is delegated wholesale to Otto's single apply core,
    # Otto::Security::CSP::Writer (Otto >= 2.5). The Writer owns every emission
    # invariant — nonce-CSP enabled, a present nonce, HTML-only responses, and
    # never clobbering a policy a downstream layer already set — and for its own
    # work reads the Content-Type / Content-Security-Policy headers
    # case-insensitively while writing the canonical lowercase
    # content-security-policy key. So none of that guard logic (nor the lowercase
    # header lookups this method used to hand-roll) lives here anymore. We hand it
    # the per-request nonce generated in #setup_request (env['onetime.nonce']) —
    # the same nonce the views stamp onto <script>/<link> tags, so what they emit
    # matches the policy — and the per-request Otto security config, which owns
    # the directive set.
    #
    # That case-insensitive reading is the Writer's own, for the headers it
    # consults. The sibling Content-Type default in #finalize_response does its
    # own case-insensitive presence check (see #ensure_content_type), so the two
    # agree on whether a Content-Type is already set no matter how it was cased.
    #
    # mode: :backstop makes this a passive layer: it fills the CSP gap for HTML
    # responses that would otherwise ship without one, but defers to (never
    # overrides) a Content-Security-Policy a route or downstream layer already
    # set. The Writer mutates the headers hash in place, so finalize_response's
    # returned tuple needs no reassignment.
    #
    # The one gate that stays app-side is the OTS site.security.csp.enabled
    # toggle (defaults on: CSP_ENABLED != 'false'); it is Onetime configuration,
    # not an Otto emission invariant.
    def emit_csp_header(headers, env)
      return unless OT.conf.dig('site', 'security', 'csp', 'enabled')

      Otto::Security::CSP::Writer.apply(
        headers,
        env['onetime.nonce'],
        config: env['otto.security_config'],
        mode: :backstop,
        development_mode: OT.conf.dig('development', 'enabled') ? true : false,
      )
    end
    end
  end
end
