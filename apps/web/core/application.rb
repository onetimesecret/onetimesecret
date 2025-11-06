# apps/web/core/application.rb

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/logging'

require_relative 'middleware/request_setup'
require_relative 'middleware/error_handling'
require_relative 'middleware/vite_proxy'

require_relative 'logic'
require_relative 'controllers'
require_relative 'auth_strategies'

module Core
  # Core Web Application
  #
  # The main web application serving the Onetime Secret frontend and HTML views.
  # Uses Otto router with custom authentication strategies and CSP nonce support.
  #
  # ## Architecture
  #
  # - Router: Otto (configured in `build_router`)
  # - Middleware: Universal (MiddlewareStack) + Core-specific (below)
  # - Otto Hooks: Includes `OttoHooks` for request lifecycle logging
  #
  class Application < Onetime::Application::Base
    include Onetime::Logging
    include Onetime::Application::OttoHooks  # Provides configure_otto_request_hook

    @uri_prefix = '/'.freeze

    # Core-specific middleware (universal middleware in MiddlewareStack)
    #
    # Initialize request context (nonce, locale) before other processing
    use Core::Middleware::RequestSetup

    # CSRF Response Header
    # Note: CSRF validation is handled by common Security middleware with
    # allow_if to skip JSON/API requests. This just adds the response header.
    use Onetime::Middleware::CsrfResponseHeader

    # Simplified error handling for Vue SPA - serves entry points
    # Must come after security but before router to catch all downstream errors
    use Core::Middleware::ErrorHandling

    Onetime.development? do
      # Enable development-specific middleware when in development mode
      # This handles code validation and frontend development server integration
      use Core::Middleware::ViteProxy

      use Rack::SessionDebugger if ENV['DEBUG_SESSION']

      # Schema validation middleware validates that hydration data matches
      # the JSON schemas generated from <schema> sections in .rue templates.
      #
      # To generate/update schemas, run:
      #   pnpm run build:schemas
      #
      # Or directly with rake:
      #   ruby -I ../rhales/lib -r rake -e "load 'Rakefile'; Rake.application.run" -- rhales:schema:generate TEMPLATES_DIR=./apps/web/core/templates OUTPUT_DIR=./public/schemas
      schemas_dir = File.expand_path('../../../../public/schemas', __dir__)
      if File.exist?(File.join(schemas_dir, 'index.json'))
        begin
          require 'rhales/middleware/schema_validator'
          use Rhales::Middleware::SchemaValidator,
            schemas_dir: schemas_dir,
            fail_on_error: true,  # Fail loudly in development
            skip_paths: [
              '/assets',
              '/api',
              '/public',
            ]
          rhales_logger.debug "Schema validation middleware enabled"
        rescue LoadError => ex
          rhales_logger.warn "Could not load schema validation middleware - json_schemer gem not available", {
            exception: ex
          }
        end
      end
    end

    Onetime.production? do
      # Serve static frontend assets in production mode
      # While reverse proxies often handle static files in production,
      # this provides a fallback capability for simpler deployments.
      use Onetime::Middleware::StaticFiles
    end

    warmup do
      # Expensive initialization tasks go here
    end

    protected

    # Build and configure Otto router instance
    #
    # Router-specific configuration happens here, after the router instance
    # is created. This is separate from universal middleware configuration
    # in MiddlewareStack.
    #
    # @return [Otto] Configured router instance
    def build_router
      routes_path = File.join(__dir__, 'routes')
      router      = Otto.new(routes_path)

      # Configure Otto request lifecycle hooks (from OttoHooks module)
      # Instance-level hook logging for operational metrics and audit trail
      configure_otto_request_hook(router)

      # IP privacy is enabled globally in common middleware stack for public
      # addresses. Must be enabled specifically for private and localhost
      # addresses. See Otto::Middleware::IPPrivacy for details
      router.enable_full_ip_privacy!

      # Enable CSP nonce support for enhanced security
      router.enable_csp_with_nonce!(debug: OT.debug?)

      # Register authentication strategies for Web Core
      Core::AuthStrategies.register_essential(router)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
