# apps/web/auth/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/logger_methods'

# Load Rodauth configuration first
require_relative 'config'

# Load Roda app
require_relative 'router'

# Load initializers
require_relative 'initializers/rodauth_migrations'

module Auth
  class Application < Onetime::Application::Base
    @uri_prefix = '/auth'

    # Auth app should only load in full mode
    def self.should_skip_loading?
      Onetime.auth_config.mode != 'full'
    end

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
      # Warmup is for preloading and preparing the router
      # Actual initialization logic is in initializers/
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
