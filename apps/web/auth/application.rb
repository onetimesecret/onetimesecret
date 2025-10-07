# apps/web/auth/application.rb

require 'onetime/application'

# Load auth dependencies first
require_relative 'config/database'
require_relative 'config/rodauth_main'
require_relative 'helpers/session_validation'
require_relative 'routes/health'
require_relative 'routes/validation'
require_relative 'routes/account'
require_relative 'routes/admin'

# Load Roda app
require_relative 'router'

module Auth
  class Application < Onetime::Application::Base
    @uri_prefix = '/auth'.freeze

    # Auth app specific middleware (common middleware is in MiddlewareStack)

    Onetime.development? do
      # Development configuration if needed
    end

    Onetime.production? do
      # Production configuration
      use Rack::Deflater  # Gzip compression

      # Security headers (some may be redundant with MiddlewareStack)
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
      # Dependencies already loaded, just warmup tasks here
    end

    protected

    def build_router
      # Return the Roda app instance
      # Unlike Otto apps, Roda apps are classes that respond to call
      Auth::Router
    end
  end
end
