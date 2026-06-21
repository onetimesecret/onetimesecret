# apps/api/v2/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative 'logic'
require_relative 'auth_strategies'

module V2
  # V2 API Application
  #
  # RESTful API for Onetime Secret v2. Serves JSON responses and uses
  # Otto router for authentication and routing. Returns string-encoded
  # values (mirroring Redis storage). For new integrations, prefer V3
  # which returns native JSON types.
  #
  # ## Architecture
  #
  # - Router: Otto (configured in `build_router`)
  # - Middleware: Universal (MiddlewareStack) + V2-specific (below)
  # - Otto Hooks: Includes `OttoHooks` for request lifecycle logging
  # - Authentication: Token-based and session-based strategies
  #
  class Application < Onetime::Application::Base
    include Onetime::Application::OttoHooks  # Provides configure_otto_request_hook

    @uri_prefix = '/api/v2'

    # V2-specific middleware (universal middleware in MiddlewareStack)
    use Rack::JSONBodyParser # TODO: Remove since we pass: builder.use Rack::Parser, parsers: @parsers

    # Warmup block placeholder for future initialization
    warmup { nil }

    protected

    # Build and configure Otto router instance
    #
    # Router-specific configuration happens here, after the router instance
    # is created. This is separate from universal middleware configuration
    # in MiddlewareStack.
    #
    # @return [Otto] Configured router instance
    def build_router
      routes_path = File.join(__dir__, 'routes.txt')
      router      = Otto.new(routes_path)

      # Configure Otto request lifecycle hooks (from OttoHooks module)
      # Instance-level hook logging for operational metrics and audit trail
      configure_otto_request_hook(router)

      # IP privacy (incl. private/localhost masking) is configured once on the
      # universal IPPrivacyMiddleware mount in MiddlewareStack via
      # ip_privacy_security_config (mask_private_ips = true). The per-router
      # enable_full_ip_privacy! call was removed to keep a single trust/privacy
      # source; the mount's idempotency makes a second pass here redundant.

      # Register authentication strategies
      V2::AuthStrategies.register_essential(router)

      # Default error responses per ADR-013 (4xx/5xx wire format).
      # Schema: { error: string, error_type: string }
      headers             = { 'content-type' => 'application/json' }
      router.not_found    = [404, headers, [{ error: 'Not Found', error_type: 'NotFound' }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error', error_type: 'ServerError' }.to_json]]

      router
    end
  end
end
