# apps/api/v3/application.rb

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative 'logic'
require_relative 'auth_strategies'

module V3
  # V3 API Application
  #
  # RESTful API for Onetime Secret v3. Serves JSON responses with native
  # JSON types (numbers, booleans, null) instead of string-serialized values.
  # Uses Otto router for authentication and routing.
  #
  # ## Key Differences from V2
  #
  # - Returns native JSON types (leveraging Familia v2's JSON storage)
  # - Public API only (account/domain endpoints in separate Account API)
  # - Backward incompatible with v2 (breaking change in response format)
  #
  # ## Architecture
  #
  # - Router: Otto (configured in `build_router`)
  # - Middleware: Universal (MiddlewareStack) + V3-specific (below)
  # - Otto Hooks: Includes `OttoHooks` for request lifecycle logging
  # - Authentication: Token-based and session-based strategies
  #
  class Application < Onetime::Application::Base
    include Onetime::Application::OttoHooks  # Provides configure_otto_request_hook

    @uri_prefix = '/api/v3'.freeze

    # V3-specific middleware (universal middleware in MiddlewareStack)
    use Rack::JSONBodyParser

    # CSRF Response Header
    # Note: CSRF validation is handled by common Security middleware with
    # allow_if to skip /api/* routes. This just adds the response header.
    use Onetime::Middleware::CsrfResponseHeader

    warmup do
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

      # Register authentication strategies
      V3::AuthStrategies.register_essential(router)

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error' }.to_json]]

      router
    end
  end
end
