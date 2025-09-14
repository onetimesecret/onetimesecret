# apps/web/core/application.rb

require_relative '../../base_application'

require_relative 'controllers'

module Core
  class Application < ::BaseApplication
    @uri_prefix = '/'.freeze

    # Session middleware
    require_relative '../../../lib/onetime/session'
    use Onetime::Session, {
      expire_after: 86400, # 24 hours
      key: 'onetime.session',
      secure: OT.conf&.dig('site', 'ssl') || false,
      httponly: true,
      same_site: :lax,
      redis_prefix: 'session'
    }

    # Common middleware stack
    use Rack::DetectHost

    # Identity resolution middleware
    require_relative '../../../lib/middleware/identity_resolution'
    use Rack::IdentityResolution

    # Auth integration middleware
    require_relative '../../../lib/auth_integration'
    use AuthIntegration::Middleware

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
      routes_path = File.join(Onetime::HOME, 'apps/web/core/routes')
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
