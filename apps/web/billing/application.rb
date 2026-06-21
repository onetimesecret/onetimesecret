# apps/web/billing/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'
require 'onetime/logger_methods'

require_relative '../core/auth_strategies'
require_relative 'controllers'
require_relative 'logic'
require_relative 'models'
require_relative 'initializers/stripe_setup'
require_relative 'initializers/billing_catalog'

module Billing
  # Billing Web Application
  #
  # Organization billing management for Onetime Secret. Handles Stripe
  # subscriptions, checkout sessions, webhooks, and customer portal.
  #
  # ## Architecture
  #
  # - Router: Otto (configured in `build_router`)
  # - Middleware: Universal (MiddlewareStack) + Billing-specific (below)
  # - Otto Hooks: Includes `OttoHooks` for request lifecycle logging
  # - Stripe Integration: Stripe-as-source-of-truth for plan data
  #
  # ## Conditional Loading
  #
  # This application is only loaded when billing.yaml exists and enabled is true.
  # See lib/onetime/application/registry.rb for loading logic.
  #
  class Application < Onetime::Application::Base
    include Onetime::LoggerMethods
    include Onetime::Application::OttoHooks  # Provides configure_otto_request_hook

    @uri_prefix = '/billing'

    # Billing app should only load when enabled in configuration
    def self.should_skip_loading?
      !Onetime.billing_config.enabled?
    end

    warmup do
      # Warmup is for preloading and preparing the router
      # Actual initialization logic is in initializers/
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

      # Register authentication strategies for Billing
      # Billing endpoints require session auth except webhooks
      Core::AuthStrategies.register_essential(router)

      # Default error responses per ADR-013 (4xx/5xx wire format).
      # Schema: { error: string, error_type: string }
      # - `error` is the user-facing message displayed by the frontend
      # - `error_type` is the discriminator the frontend branches on (Ruby class name)
      #
      # Typed Onetime exceptions raised from logic classes are rendered by the
      # per-class handlers registered above in configure_otto_request_hook.
      # These router-level defaults catch routing-layer 404s (no matching route)
      # and uncaught 500s (exceptions Otto's handlers don't cover).
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
end
