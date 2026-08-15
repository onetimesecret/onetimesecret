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

    # Declared middleware profile: Deflater + the Rack::Protection
    # security stack (ContentSecurityPolicy, FrameOptions, HttpOrigin,
    # IPSpoofing, PathTraversal, SessionHijacking), resolved from
    # Onetime::Middleware::Registry at build time in Base#build_rack_app and
    # gated by site.middleware.profiles.authenticated_web.<key> config
    # (defaults ship all keys ON, so the stack is identical in every
    # environment — no more production-only block).
    #
    # The Registry's HttpOrigin entry carries the shared
    # Onetime::Middleware::HttpOriginOptions.options: its allow_if reads
    # env['onetime.display_domain'] so custom-domain /auth POSTs behind a
    # Host-rewriting proxy aren't rejected with 403 before reaching a route;
    # SSO initiation is the most visible affected flow.
    middleware_profile :authenticated_web

    # Auth app specific middleware (common middleware is in MiddlewareStack)
    use Rack::JSONBodyParser  # Parse JSON request bodies for Rodauth

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
