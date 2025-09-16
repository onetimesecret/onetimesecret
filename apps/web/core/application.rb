# apps/web/core/application.rb

require_relative '../../base_application'

require_relative 'controllers'

module Core
  class Application < ::BaseApplication
    @uri_prefix = '/'.freeze

    # Common middleware stack
    use Rack::ClearSessionMessages
    use Rack::DetectHost

    # Applications middleware stack
    use Onetime::DomainStrategy

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
      is_enabled = OT.conf.dig('site', 'interface', 'ui', 'enabled') || false

      enabled_routes_path = File.join(ENV['ONETIME_HOME'], 'apps/web/core/routes')
      disabled_routes_path = File.join(ENV['ONETIME_HOME'], 'apps/web/core/routes.disabled')

      routes_path = is_enabled ? enabled_routes_path : disabled_routes_path
      router      = Otto.new(routes_path)

      # Enable CSP nonce support for enhanced security
      router.enable_csp_with_nonce!(debug: OT.debug?)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
