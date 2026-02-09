# apps/api/v1/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'

require_relative 'logic'
require_relative 'controllers'
require_relative 'utils'

module V1
  # V1 API Application
  #
  # Legacy RESTful API for Onetime Secret v1. Maintained for backward
  # compatibility with existing integrations. Serves JSON responses
  # and uses Otto router with controller-based routing.
  #
  # ## Architecture
  #
  # - Router: Otto (configured in `build_router`)
  # - Middleware: Universal (MiddlewareStack) + V1-specific (below)
  # - Otto Hooks: Includes `OttoHooks` for request lifecycle logging
  # - Authentication: HTTP Basic Auth with API token
  #
  # ## API Compatibility
  #
  # This API maintains the original v1 endpoint signatures for backward
  # compatibility. Uses centralized Onetime:: models rather than
  # V1-namespaced models.
  #
  class Application < Onetime::Application::Base
    include Onetime::Application::OttoHooks

    @uri_prefix = '/api/v1'

    # V1-specific middleware (universal middleware in MiddlewareStack)
    use Rack::JSONBodyParser

    warmup do
    end

    protected

    # Build and configure Otto router instance
    #
    # @return [Otto] Configured router instance
    def build_router
      routes_path = File.join(__dir__, 'routes.txt')
      router      = Otto.new(routes_path)

      # Configure Otto request lifecycle hooks (from OttoHooks module)
      configure_otto_request_hook(router)

      # IP privacy is enabled globally in common middleware stack for public
      # addresses. Must be enabled specifically for private and localhost
      # addresses. See Otto::Middleware::IPPrivacy for details
      router.enable_full_ip_privacy!

      # Default error responses
      headers             = { 'content-type' => 'application/json' }
      product_name        = OT.conf.dig('brand', 'product_name') || 'OTS'
      router.not_found    = [404, headers, [{ error: 'Not Found', service: product_name }.to_json]]
      router.server_error = [500, headers, [{ error: 'Internal Server Error', service: product_name }.to_json]]

      router
    end
  end
end
