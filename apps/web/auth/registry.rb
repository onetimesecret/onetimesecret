# apps/web/auth/application.rb

require 'bundler/setup'
require 'base_application'

require_relative 'app'

module Auth
  class Application < ::BaseApplication
    @uri_prefix = '/auth'.freeze

    # Auth app specific middleware (common middleware is in MiddlewareStack)

    # Development Environment Configuration
    # Enable development-specific middleware when in development mode
    # This handles code validation and frontend development server integration
    Onetime.development? do

    end

    # Serve static frontend assets in production mode
    # While reverse proxies often handle static files in production,
    # this provides a fallback capability for simpler deployments.
    Onetime.production? do
      # Production configuration
      use Rack::Deflater  # Gzip compression

      # Security headers
      use Rack::Protection::AuthenticityToken
      use Rack::Protection::ContentSecurityPolicy
      use Rack::Protection::FrameOptions
      use Rack::Protection::HttpOrigin
      use Rack::Protection::IPSpoofing
      use Rack::Protection::JsonCsrf
      use Rack::Protection::PathTraversal
      use Rack::Protection::SessionHijacking
    end

    warmup do
      # Expensive initialization tasks go here

      # Log warmup completion
      Onetime.li 'Auth warmup completed'
    end

    protected

    def build_router
      # Return the Roda app instance directly (not frozen)
      AuthService.app
    end
  end
end

# Register the Auth application with the application registry
AppRegistry.register_application_class(Auth::Application)
