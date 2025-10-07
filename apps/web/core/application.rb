# apps/web/core/application.rb

require 'onetime/application'
require 'onetime/middleware'

require_relative 'controllers'

module Core
  class Application < Onetime::Application::Base
    @uri_prefix = '/'.freeze

    # App-specific middleware (common middleware is in MiddlewareStack)

    # Development Environment Configuration
    # Enable development-specific middleware when in development mode
    # This handles code validation and frontend development server integration
    Onetime.development? do
      require 'onetime/middleware/vite_proxy'
      use Onetime::Middleware::ViteProxy
    end

    # # Serve static frontend assets in production mode
    # # While reverse proxies often handle static files in production,
    # # this provides a fallback capability for simpler deployments.
    Onetime.production? do
      require 'onetime/middleware/static_files'
      use Onetime::Middleware::StaticFiles
    end

    warmup do
      # Expensive initialization tasks go here

      # Log warmup completion
      Onetime.li 'Core warmup completed'
    end

    protected

    def build_router
      routes_path = File.join(Onetime::HOME, 'apps/web/core/routes')
      router      = Otto.new(routes_path)

      # Enable CSP nonce support for enhanced security
      router.enable_csp_with_nonce!(debug: OT.debug?)

      # Register authentication strategies for Web Core
      require_relative 'auth_strategies'
      Core::AuthStrategies.register_all(router)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
