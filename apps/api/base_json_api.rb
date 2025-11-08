# apps/api/base_json_api.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'

# BaseJSONAPI
#
# Shared base class for JSON API applications (v3 and Account API).
# Provides common middleware stack, router configuration, and error handling.
#
# ## Purpose
#
# Centralizes the common setup for modern JSON APIs that:
# - Serve native JSON types (leveraging Familia v2)
# - Use Otto router for authentication and routing
# - Follow REST conventions with proper error responses
#
# ## Usage
#
# Subclasses must define:
# - @uri_prefix class variable
# - self.auth_strategy_module class method
# - self.root_path class method
#
# Example:
#
#   class V3::Application < BaseJSONAPI
#     @uri_prefix = '/api/v3'.freeze
#     def self.auth_strategy_module; V3::AuthStrategies; end
#     def self.root_path; __dir__; end
#   end
#
class BaseJSONAPI < Onetime::Application::Base
  include Onetime::Application::OttoHooks

  # Mark as abstract - should not be mounted directly
  @abstract = true

  # Common middleware for all JSON APIs
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
  # Subclasses must define:
  # - self.auth_strategy_module to return the auth module
  # - self.root_path to return the directory containing routes/
  #
  # @return [Otto] Configured router instance
  def build_router
    routes_path = File.join(self.class.root_path, 'routes')
    router      = Otto.new(routes_path)

    # Configure Otto request lifecycle hooks (from OttoHooks module)
    # Instance-level hook logging for operational metrics and audit trail
    configure_otto_request_hook(router)

    # IP privacy is enabled globally in common middleware stack for public
    # addresses. Must be enabled specifically for private and localhost
    # addresses. See Otto::Middleware::IPPrivacy for details
    router.enable_full_ip_privacy!

    # Register authentication strategies
    self.class.auth_strategy_module.register_essential(router)

    # Default error responses matching v3 REST schema
    # Schema: { message: string, code?: string, details?: object }
    # Note: No 'success' field - HTTP status codes indicate success/error
    headers = { 'content-type' => 'application/json' }
    router.not_found = [
      404,
      headers,
      [{ message: 'Not Found', code: 'NOT_FOUND' }.to_json]
    ]
    router.server_error = [
      500,
      headers,
      [{ message: 'Internal Server Error', code: 'SERVER_ERROR' }.to_json]
    ]

    router
  end
end
