# apps/web/billing/application.rb

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'
require 'onetime/logging'

require_relative 'controllers'
require_relative 'models'

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
  # This application is only loaded when `conf.dig('billing', 'enabled')` is true.
  # See lib/onetime/application/registry.rb for loading logic.
  #
  class Application < Onetime::Application::Base
    include Onetime::Logging
    include Onetime::Application::OttoHooks  # Provides configure_otto_request_hook

    @uri_prefix = '/billing'.freeze

    # CSRF Response Header
    # Note: CSRF validation is handled by common Security middleware with
    # allow_if to skip webhook endpoints. This just adds the response header.
    use Onetime::Middleware::CsrfResponseHeader

    warmup do
      # Refresh plan cache from Stripe on application boot
      billing_logger.info "Refreshing plan cache from Stripe"
      begin
        Billing::Models::PlanCache.refresh_from_stripe
        billing_logger.info "Plan cache refreshed successfully"
      rescue StandardError => ex
        billing_logger.error "Failed to refresh plan cache", {
          exception: ex,
          message: ex.message
        }
      end
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

      # Register authentication strategies for Billing
      # Billing endpoints require session auth except webhooks
      Core::AuthStrategies.register_essential(router)

      # Default error responses
      headers             = { 'content-type' => 'text/html' }
      router.not_found    = [404, headers, ['Not Found']]
      router.server_error = [500, headers, ['Internal Server Error']]

      router
    end
  end
end
