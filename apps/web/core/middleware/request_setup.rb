# apps/web/core/middleware/request_setup.rb
#
# frozen_string_literal: true

require 'onetime/logging'

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
      include Onetime::Logging

      def initialize(app, default_content_type: 'text/html; charset=utf-8')
        @app = app
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
      nonce = SecureRandom.base64(16)
      env['onetime.nonce'] = nonce

      # Locale is handled by Otto::Locale::Middleware
      # Available via env['otto.locale']

      http_logger.debug "Request setup complete", { nonce: nonce[0, 8] } if OT.debug?
    end

    def finalize_response(status, headers, body, env)
      # Set default Content-Type if not already set
      headers['content-type'] ||= @default_content_type

      [status, headers, body]
    end


    end
  end
end
