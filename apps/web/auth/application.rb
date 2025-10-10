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
      # Auto-run migrations in advanced mode
      # This ensures the database schema is ready when Rodauth is enabled
      if Onetime.auth_config.advanced_enabled?
        begin
          require_relative 'migrator'
          Auth::Migrator.run_if_needed
          OT.info "Auth database migrations completed (advanced mode)"
        rescue StandardError => e
          OT.le "Failed to run auth database migrations: #{e.message}"
          # Don't fail startup in production, log the error
          raise e if Onetime.development?
        end
      else
        OT.le "[Auth::Application] WARNING: Auth application should not be mounted in basic mode"
        OT.le "  The Auth app is designed for advanced mode only."
        OT.le "  In basic mode, authentication is handled by Core app at /auth/*"
        OT.le "  Check your application registry configuration."
      end
    end

    protected

    def build_router
      # Return the Roda app instance
      # Unlike Otto apps, Roda apps are classes that respond to call
      Auth::Router
    end
  end
end
