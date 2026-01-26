# lib/onetime/middleware/csrf_response_header.rb
#
# frozen_string_literal: true

require 'rack/protection'

module Onetime
  module Middleware
    ##
    # CsrfResponseHeader
    #
    # Adds CSRF token to response headers after Rack::Protection::AuthenticityToken
    # validates the request.
    #
    # This middleware ensures the CSRF token is available to the frontend via
    # the X-CSRF-Token response header. The token is MASKED using the same
    # algorithm that Rack::Protection uses for form tokens.
    #
    # **Why masked tokens?**
    # Rack::Protection::AuthenticityToken stores a raw token in session[:csrf]
    # but validates against MASKED tokens (XOR + base64). Returning the raw
    # token would fail validation. Using .token(session) returns the properly
    # masked version that the middleware will accept.
    #
    # **Why separate middleware?**
    # Rack::Protection handles validation but doesn't add the token to response
    # headers. This middleware complements it for JSON/AJAX usage.
    #
    # Usage:
    #   use Rack::Protection::AuthenticityToken
    #   use Onetime::Middleware::CsrfResponseHeader
    #
    class CsrfResponseHeader
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        # Get properly masked CSRF token from Rack::Protection
        # This returns a masked token that will pass validation
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
