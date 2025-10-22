# apps/web/auth/application.rb

require 'onetime/application'
require 'onetime/logging'

# Load auth dependencies first
require_relative 'config/database'
require_relative 'config'
require_relative 'helpers/session_validation'
require_relative 'routes/health'
require_relative 'routes/validation'
require_relative 'routes/account'
require_relative 'routes/admin'

# Load Roda app
require_relative 'router'

module Auth
  class Application < Onetime::Application::Base
    # include Onetime::Logging # call Onetime.auth_logger directly due to all the blocks

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
      # Migrations are run in build_router before loading the Router class
      # This warmup block can be used for other initialization tasks if needed
      if Onetime.auth_config.advanced_enabled?
        Onetime.auth_logger.info 'Auth application initialized (advanced mode)'
      else
        Onetime.auth_logger.error "Auth application mounted in basic mode - this is a configuration error. " \
          "The Auth app is designed for advanced mode only. In basic mode, authentication " \
          "is handled by Core app at /auth/*. Check your application registry configuration.",
          app: "Auth::Application",
          mode: "basic",
          expected_mode: "advanced"
      end
    end

    protected

    def build_router
      # Run migrations BEFORE loading the Router class
      # This ensures database tables exist when Rodauth validates features during plugin load
      if Onetime.auth_config.advanced_enabled?
        begin
          require_relative 'migrator'
          Auth::Migrator.run_if_needed
          Onetime.auth_logger.debug 'Auth database migrations completed before router load'
        rescue StandardError => ex
          Onetime.auth_logger.error "Auth database migrations failed before router load", exception: ex
          raise ex if Onetime.development?
        end
      end

      # Return the Roda app instance
      # Unlike Otto apps, Roda apps are classes that respond to call
      Auth::Router
    end
  end
end
