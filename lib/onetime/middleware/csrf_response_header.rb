# lib/onetime/middleware/csrf_response_header.rb

module Onetime
  module Middleware
    ##
    # CsrfResponseHeader
    #
    # Adds CSRF token to response headers after Rack::Protection::JsonCsrf
    # validates the request.
    #
    # This middleware is a thin wrapper that ensures the CSRF token is
    # available to the frontend via the X-CSRF-Token response header.
    #
    # **Why separate middleware?**
    # Rack::Protection::JsonCsrf handles validation but doesn't add the
    # token to response headers (it's designed for HTML meta tags).
    # This middleware complements it for JSON API usage.
    #
    # **Alternative approach:**
    # We could create a single consolidated middleware that both validates
    # and adds headers, but keeping them separate:
    # - Follows single responsibility principle
    # - Leverages battle-tested Rack::Protection for validation
    # - Keeps our custom code minimal and focused
    #
    # Usage:
    #   use Rack::Protection::JsonCsrf
    #   use Onetime::Middleware::CsrfResponseHeader
    #
    class CsrfResponseHeader
      def initialize(app)
        @app = app
      end

      def call(env)
        status, headers, body = @app.call(env)

        # Read CSRF token from session (Rack::Protection stores as :csrf)
        session = env['rack.session']
        csrf_token = session&.[](:csrf) || session&.[]('csrf')

        # Add to response headers if present
        headers['X-CSRF-Token'] = csrf_token if csrf_token

        [status, headers, body]
      end
    end
  end
end
