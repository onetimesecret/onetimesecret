# lib/onetime/middleware/csrf_response_header.rb
#
# frozen_string_literal: true

module Onetime
  module Middleware
    ##
    # CsrfResponseHeader
    #
    # Adds a masked CSRF token to response headers for frontend consumption.
    #
    # Rack::Protection::AuthenticityToken handles validation and stores
    # a raw token in session[:csrf]. Rather than exposing that raw token
    # directly (which would be vulnerable to BREACH attacks on compressed
    # HTTPS responses), this middleware uses AuthenticityToken.token() to
    # return a per-request masked version. The masked token is XOR'd with
    # a one-time pad, so the header value changes on every response while
    # still validating against the same underlying session token.
    #
    # Usage:
    #   use Rack::Protection::AuthenticityToken  # validates requests
    #   use Onetime::Middleware::CsrfResponseHeader  # exposes masked token
    #
    class CsrfResponseHeader
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        session = env['rack.session']
        if session
          csrf_token              = Rack::Protection::AuthenticityToken.token(session)
          headers['X-CSRF-Token'] = csrf_token if csrf_token
        end

        [status, headers, body]
      end
    end
  end
end
