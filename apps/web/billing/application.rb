# apps/web/billing/application.rb
#
# frozen_string_literal: true

require 'onetime/application'
require 'onetime/application/otto_hooks'
require 'onetime/middleware'
require 'onetime/models'
require 'onetime/logger_methods'

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
  # This application is only loaded when billing.yaml exists and enabled is true.
  # See lib/onetime/application/registry.rb for loading logic.
  #
  class Application < Onetime::Application::Base
    include Onetime::LoggerMethods
    include Onetime::Application::OttoHooks  # Provides configure_otto_request_hook

    @uri_prefix = '/billing'.freeze

    # Billing app should only load when enabled in configuration
    def self.should_skip_loading?
      !Onetime.billing_config.enabled?
    end

    # CSRF Response Header
    # Note: CSRF validation is handled by common Security middleware with
    # allow_if to skip webhook endpoints. This just adds the response header.
    use Onetime::Middleware::CsrfResponseHeader

    warmup do
      # We do this here to take care of our own initialization needs.
      stripe_key = Onetime.billing_config.stripe_key
      if stripe_key && !stripe_key.to_s.strip.empty?
        Stripe.api_key = stripe_key
        Onetime.billing_logger.info 'Stripe API key configured'
      else
        Onetime.billing_logger.warn 'Stripe API key not configured - billing features disabled'
      end

      # Refresh plan cache from Stripe on application boot
      Onetime.billing_logger.info 'Refreshing plan cache from Stripe'
      begin
        Billing::Plan.refresh_from_stripe
        Onetime.billing_logger.info 'Plan cache refreshed successfully'
      rescue StandardError => ex
        Onetime.billing_logger.error 'Failed to refresh plan cache', {
          exception: ex,
          message: ex.message,
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
      routes_path = File.join(__dir__, 'routes.txt')
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
