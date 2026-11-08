# apps/api/base_json_api.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'rack/head'

# BaseJSONAPI
#
# Shared base class for JSON API applications (v3, Incoming and Account APIs).
# Provides common middleware stack, router configuration, and error handling.
#
# ## Purpose
#
# Centralizes the common setup for modern JSON APIs that:
# - Serve native JSON types (leveraging Familia v2)
# - Use Otto router for authentication and routing
# - Use version-specific routes and response envelopes
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

  # Shared method boundary. Do not register HEAD routes: Otto 2.11 mutates
  # their stored containers during dispatch, which fails after config freezes.
  class HTTPMethods
    # Otto freezes the configured factory itself. Keep it separate from the
    # route target, which Otto decorates with per-request helpers.
    class HandlerFactory
      def self.create_handler(route, router)
        factory = Otto::RouteHandlers::HandlerFactory
        return factory.create_handler(route, router) unless route.option(:head) == 'reject'

        refusal = Otto::RouteDefinition.new(
          route.verb,
          route.path,
          route.definition.sub(/\A\S+/, "#{HTTPMethods.name}.reject_head"),
          pattern: route.pattern,
          keys: route.keys,
        )
        # Only replace the target, not Otto's auth/CSRF/registered wrapper chain.
        # The refusal executes after the matched GET route's authentication.
        ->(env, params = {}) do
          target = env['REQUEST_METHOD'] == 'HEAD' ? refusal : route
          factory.create_handler(target, router).call(env, params)
        end
      end
    end

    # Acknowledges the method without granting CORS or running creation logic.
    def self.options(_req, res)
      res.status = 204
      res.body   = []
      nil
    end

    def self.reject_head(req, res)
      path                 = Otto::Utils.normalize_path(req.path_info)
      allowed              = otto.routes.filter_map do |verb, routes|
        verb.to_s if routes.any? { |route| route.pattern.match?(path) }
      end
      res.status           = 405
      res.headers['allow'] = allowed.join(', ')
      res.body             = []
      nil
    end
  end

  # Mark as abstract - should not be mounted directly
  @abstract = true

  # BaseJSONAPI deliberately registers no class-level middleware.
  # It previously registered Rack::JSONBodyParser here, but the class-level
  # `middleware` ivar did not inherit and BaseJSONAPI itself is abstract (never
  # instantiated), so that registration was dead code — subclasses never
  # mounted it. Middleware resolution now inherits (Base.resolved_middleware),
  # so re-adding a `use` here WOULD apply to every subclass; the line stays
  # removed to keep today's resolved stacks identical. JSON request-body
  # parsing is already covered by Rack::Parser in the universal MiddlewareStack
  # (plus v1/v2's own explicit Rack::JSONBodyParser mounts).

  # Warmup block placeholder for future initialization
  warmup { nil }

  protected

  # Wrap the entire application, including early parser/security refusals.
  # Body suppression alone is insufficient for one-time reads; V2/V3 routes
  # use the method boundary before those handlers can consume a value.
  def build_rack_app
    Rack::Head.new(super)
  end

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
    routes_path = File.join(self.class.root_path, 'routes.txt')
    router      = Otto.new(routes_path, route_handler_factory: HTTPMethods::HandlerFactory)

    # Configure Otto request lifecycle hooks (from OttoHooks module)
    # Instance-level hook logging for operational metrics and audit trail
    configure_otto_request_hook(router)

    # IP privacy (incl. private/localhost masking) is configured once on the
    # universal IPPrivacyMiddleware mount in MiddlewareStack via
    # ip_privacy_security_config (mask_private_ips = true). The per-router
    # enable_full_ip_privacy! call was removed to keep a single trust/privacy
    # source; the mount's idempotency makes a second pass here redundant.

    # Register authentication strategies
    self.class.auth_strategy_module.register_essential(router)

    # Router fallback responses only. Auth, parser, CSRF and typed logic
    # errors use their own boundaries; ADR-013 is still proposed.
    # Schema: { error: string, error_type: string }
    # - `error` is the user-facing message displayed by the frontend
    # - `error_type` is the discriminator the frontend branches on (Ruby class name)
    # Note: No 'success' field - HTTP status codes indicate success/error
    headers             = { 'content-type' => 'application/json' }
    router.not_found    = [
      404,
      headers,
      [{ error: 'Not Found', error_type: 'NotFound' }.to_json],
    ]
    router.server_error = [
      500,
      headers,
      [{ error: 'Internal Server Error', error_type: 'ServerError' }.to_json],
    ]

    router
  end
end
