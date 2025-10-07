# apps/web/core/application.rb

require 'onetime/application'
require 'onetime/middleware'

require_relative 'app'

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
      # Return the Core app instance
      Core::App.new
    end
  end
end
