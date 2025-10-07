# apps/web/core/application.rb

require 'onetime/application'
require 'onetime/middleware'

require_relative 'middleware/request_setup'
require_relative 'middleware/error_handling'
require_relative 'middleware/vite_proxy'

require_relative 'controllers'
require_relative 'auth_strategies'

module Core
  class Application < Onetime::Application::Base
    @uri_prefix = '/'.freeze

    # Initialize request context (nonce, locale) before other processing
    use Core::Middleware::RequestSetup

    # Simplified error handling for Vue SPA - serves entry points
    # Must come after security but before router to catch all downstream errors
    use Core::Middleware::ErrorHandling

    Onetime.development? do
      # Enable development-specific middleware when in development mode
      # This handles code validation and frontend development server integration
      use Core::Middleware::ViteProxy
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

    def build_router
      routes_path = File.join(__dir__, 'routes')
      router      = Otto.new(routes_path)

      # Enable CSP nonce support for enhanced security
      router.enable_csp_with_nonce!(debug: OT.debug?)

      # Register authentication strategies for Web Core
      Core::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
