# lib/onetime/middleware/csrf_response_header.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    ##
    # CsrfResponseHeader
    #
    # Adds CSRF token to response headers for frontend consumption.
    #
    # Rack::Protection::AuthenticityToken handles validation and stores
    # the token in session[:csrf]. This middleware reads that token and
    # exposes it via the X-CSRF-Token response header for axios to use.
    #
    # Usage:
    #   use Rack::Protection::AuthenticityToken  # validates requests
    #   use Onetime::Middleware::CsrfResponseHeader  # exposes token
    #
    class CsrfResponseHeader
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        # Read CSRF token from session (Rack::Protection stores as :csrf)
        session    = env['rack.session']
        csrf_token = session&.[](:csrf) || session&.[]('csrf')

        # Add to response headers if present
        headers['X-CSRF-Token'] = csrf_token if csrf_token

        [status, headers, body]
      end
    end
  end
end
