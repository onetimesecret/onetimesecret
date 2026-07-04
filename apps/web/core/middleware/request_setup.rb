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
      # Default the Content-Type when a route left it unset.
      #
      # This lookup is lowercase-only, and is safe only because of how this
      # middleware is scoped: it wraps just the Core app (mounted at '/'), whose
      # downstream layers emit lowercase response-header keys throughout (see the
      # lowercase 'content-type' defaults in application.rb). The apps that set a
      # canonically-cased 'Content-Type' (auth, billing) mount at their own
      # prefixes with separate stacks and never pass through here — so a Core
      # response never carries a capital-cased 'Content-Type' that this ||= would
      # fail to see and then double-write. (Writer.apply below reads Content-Type
      # case-insensitively; this ||= does not, and leans on that Core-only
      # scoping to stay correct.)
      headers['content-type'] ||= @default_content_type

      emit_csp_header(headers, env)

      [status, headers, body]
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
    # consults; it does not retroactively make finalize_response's lowercase-only
    # 'content-type' default (above) casing-safe — that line stays correct under
    # the Core-only scoping documented there.
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
