# apps/web/auth/application.rb

require 'onetime/application'
require 'onetime/logging'

# Load Rodauth configuration first
require_relative 'config'

# Load Roda app
require_relative 'router'

module Auth
  class Application < Onetime::Application::Base
    @uri_prefix = '/auth'.freeze

    # Auth app specific middleware (common middleware is in MiddlewareStack)
    use Rack::JSONBodyParser  # Parse JSON request bodies for Rodauth

    # CSRF Response Header
    # Note: CSRF validation is handled by common Security middleware with
    # allow_if to skip JSON requests. Rodauth json feature disables CSRF internally.
    use Onetime::Middleware::CsrfResponseHeader

    Onetime.development? do
      # Development configuration if needed
    end

    Onetime.production? do
      # Production configuration
      use Rack::Deflater  # Gzip compression

      # Additional security headers (some may be redundant with MiddlewareStack)
      use Rack::Protection::ContentSecurityPolicy
      use Rack::Protection::FrameOptions
      use Rack::Protection::HttpOrigin
      use Rack::Protection::IPSpoofing
      use Rack::Protection::PathTraversal
      use Rack::Protection::SessionHijacking
    end

    warmup do
      # Migrations are run in build_router before loading the Router class
      # This warmup block can be used for other initialization tasks if needed
      if Onetime.auth_config.advanced_enabled?
      # Run migrations BEFORE loading the Router class
      # This ensures database tables exist when Rodauth validates features during plugin load

        # Require Auth::Migrator only when needed (after config is loaded)
        #
        # apps/web needs to be in $LOAD_PATH already for this to work
        require 'auth/migrator'

        Auth::Migrator.run_if_needed
        # Onetime.auth_logger.warn "Calling Sequel::Migrator.run is disabled."

        Onetime.auth_logger.debug 'Auth application initialized (advanced mode)'
      else
        Onetime.auth_logger.error 'Auth application mounted in basic mode - this is a configuration error. ' \
                                  'The Auth app is designed for advanced mode only. In basic mode, authentication ' \
                                  'is handled by Core app at /auth/*. Check your application registry configuration.',
          app: 'Auth::Application',
          mode: 'basic',
          expected_mode: 'advanced'
      end
    end

    protected

    def build_router

      # NOTE: Make sure that migrations BEFORE we get here to load the Router
      # class. This ensures database tables exist when Rodauth validates
      # features during plugin load.

      # Unlike Otto apps, Roda apps are classes that respond to call so
      # we return the class itself here.
      Auth::Router
    end
  end
end
