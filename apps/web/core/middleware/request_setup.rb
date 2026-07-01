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
      # Set default Content-Type if not already set
      headers['content-type'] ||= @default_content_type

      emit_csp_header(headers, env)

      [status, headers, body]
    end

    # Emit the Content-Security-Policy header for HTML responses.
    #
    # The policy itself is delegated to Otto (the single policy source): its
    # security config owns the directive set, and we hand it the per-request
    # nonce generated in #setup_request — the same nonce the views stamp onto
    # <script>/<link> tags, so what they emit matches the policy. We set the
    # header here rather than via Otto::Response#send_csp_headers because this
    # Rack chokepoint works with a raw response tuple, not a Response object;
    # #generate_nonce_csp is the config-level primitive that helper wraps.
    #
    # Guards (any short-circuits to a no-op):
    # - OFF unless site.security.csp.enabled is true (default false), so this is
    #   inert until deliberately enabled and validated against the SPA.
    # - HTML responses only (JSON/redirects/static are left untouched).
    # - Never clobbers a Content-Security-Policy a downstream layer already set.
    # - Requires Otto nonce-CSP support and a present nonce.
    def emit_csp_header(headers, env)
      return unless OT.conf.dig('site', 'security', 'csp', 'enabled')
      return unless headers['content-type']&.start_with?('text/html')
      return if headers['content-security-policy']

      security_config = env['otto.security_config']
      return unless security_config&.csp_nonce_enabled?

      nonce = env['onetime.nonce']
      return if nonce.nil? || nonce.empty?

      development_mode = OT.conf.dig('development', 'enabled') ? true : false
      headers['content-security-policy'] =
        security_config.generate_nonce_csp(nonce, development_mode: development_mode)
    end
    end
  end
end
