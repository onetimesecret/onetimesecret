# apps/web/core/application.rb

require 'base_application'
require 'onetime/middleware'

require_relative 'app'

module Core
  class Application < ::BaseApplication
    @uri_prefix = '/'.freeze

    # Common middleware stack
    use Rack::DetectHost

    # Identity resolution middleware
    use Onetime::Middleware::IdentityResolution

    # Applications middleware stack
    use Onetime::Middleware::DomainStrategy

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
