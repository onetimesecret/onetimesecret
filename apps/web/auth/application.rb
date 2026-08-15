# apps/web/auth/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/logger_methods'
require 'onetime/middleware/http_origin_options'

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

    # Declared middleware profile (#4170 step 2): the config-gated registry
    # components this app mounts beyond the universal stack. Until step 3
    # lands config defaults for the profile's site.middleware keys, the
    # profile resolves to nothing extra and the production? block below
    # remains the effective production mount path.
    middleware_profile :authenticated_web

    # Auth app specific middleware (common middleware is in MiddlewareStack)
    use Rack::JSONBodyParser  # Parse JSON request bodies for Rodauth

    Onetime.development? do
      # Development configuration if needed
    end

    # NOTE (#4170 step 3): this entire production-only block is superseded by
    # the :authenticated_web middleware_profile above once config defaults for
    # its site.middleware keys land — step 3 removes it.
    Onetime.production? do
      # Production configuration
      use Rack::Deflater  # Gzip compression

      # Additional security headers (some may be redundant with MiddlewareStack)
      use Rack::Protection::ContentSecurityPolicy
      use Rack::Protection::FrameOptions
      # Shared options with the main app's Security mount (#4170): without the
      # allow_if reading env['onetime.display_domain'], custom-domain /auth
      # POSTs behind a Host-rewriting proxy are rejected with 403 before
      # reaching a route (SSO initiation being the most visible casualty).
      # NOTE: unlike the Security mount, this one ignores the
      # site.middleware.http_origin toggle and is production-only.
      use Rack::Protection::HttpOrigin, **Onetime::Middleware::HttpOriginOptions.options
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
