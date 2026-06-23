# lib/onetime/application/otto_hooks.rb
#
# frozen_string_literal: true

#
# Shared Otto request lifecycle hooks for Otto-based applications.
#
# This module provides common Otto hook configurations that can be included
# by applications using Otto as their router (Core, V2). Applications using
# other routers (Auth/Roda) do not need these hooks.

require_relative '../logger_methods'
require_relative 'request_helpers'
require_relative 'error_resolver'
require_relative 'middleware_stack'

module Onetime
  module Application
    module OttoHooks
      include Onetime::LoggerMethods

      # Configure Otto request completion hook for operational metrics
      #
      # Logs every completed request with timing, status, and authentication context.
      # This provides a centralized audit trail for all HTTP requests through Otto.
      #
      # @param router [Otto] The Otto router instance to configure
      # @return [void]
      #
      # @example
      #   def build_router
      #     router = Otto.new(routes_path)
      #     configure_otto_request_hook(router)
      #     router
      #   end
      def configure_otto_request_hook(router)
        # Register Onetime-specific request helpers
        router.register_request_helpers(Onetime::Application::RequestHelpers)

        # Register expected errors with status codes and log levels. Errors
        # carrying an i18n error_key get resolved by ErrorResolver before
        # to_h serializes them. Errors without an error_key are left as-is
        # so legacy callers continue to render their pre-resolved message.
        #
        # Otto matches handlers by exact class, so subclasses (MissingSecret
        # < RecordNotFound, EntitlementRequired < Forbidden, LimitExceeded
        # < Forbidden) each need their own registration even when the body
        # block is identical.

        not_found_handler = ->(error, req) {
          Onetime::Application::ErrorResolver.resolve!(error, req)
          body = error.respond_to?(:to_h) ? error.to_h : { message: error.message || 'Not Found' }
          with_error_correlation(body, req, error)
        }
        router.register_error_handler(Onetime::RecordNotFound, status: 404, log_level: :info, &not_found_handler)
        router.register_error_handler(Onetime::MissingSecret, status: 404, log_level: :info, &not_found_handler)

        # Form errors return 422 with error type and field info
        router.register_error_handler(Onetime::FormError, status: 422, log_level: :info) do |error, req|
          Onetime::Application::ErrorResolver.resolve!(error, req)
          with_error_correlation(error.to_h, req, error)
        end

        # Forbidden errors return 403. Resolver localizes when error_key is
        # present; pure-legacy callers (no error_key) get the response built
        # from the pre-resolved message untouched.
        router.register_error_handler(Onetime::Forbidden, status: 403, log_level: :warn) do |error, req|
          Onetime::Application::ErrorResolver.resolve!(error, req)
          body = error.respond_to?(:to_h) ? error.to_h : { message: error.message }
          with_error_correlation(body, req, error)
        end

        # Rate limit exceeded errors return 429 with retry info
        router.register_error_handler(Onetime::LimitExceeded, status: 429, log_level: :warn) do |error, req|
          Onetime::Application::ErrorResolver.resolve!(error, req)
          with_error_correlation(error.to_h, req, error)
        end

        # Entitlement errors return 403 with upgrade path info
        # NOTE: Otto handles Content-Type header automatically; handler returns body hash only
        router.register_error_handler(Onetime::EntitlementRequired, status: 403, log_level: :info) do |error, req|
          with_error_correlation(error.to_h, req, error)
        end

        # Guest routes disabled errors return 403 with error code
        router.register_error_handler(Onetime::GuestRoutesDisabled, status: 403, log_level: :info) do |error, req|
          Onetime::Application::ErrorResolver.resolve!(error, req)
          with_error_correlation(error.to_h, req, error)
        end

        # Unauthorized errors return 401. Onetime::Unauthorized is a marker
        # class (no #to_h); messages are caller-supplied and verified
        # non-sensitive across call sites ('Invalid credentials',
        # 'Not authorized to update this receipt'). Symmetric with
        # Auth::ErrorTranslator so the Roda and Otto layers agree.
        router.register_error_handler(Onetime::Unauthorized, status: 401, log_level: :warn) do |error, req|
          with_error_correlation({ error: error.message, error_type: 'Unauthorized' }, req, error)
        end

        # Plan-catalog cache misses (Billing::PlanCacheMissError) are a known,
        # expected backend condition: the Stripe-synced plan catalog isn't
        # populated (or a stale plan_id no longer resolves), so org plan/limit
        # resolution fails closed in WithMaterializedLimits/WithPlanEntitlements.
        # That is an ops problem, not an unexpected crash, so it must not surface
        # as an unhandled 500 on otherwise-valid read endpoints (account
        # permissions, domains list, organizations). Return 503 with a safe,
        # generic message — never the error's internal "cache or config" wording
        # or the plan_id/organization_id it carries.
        #
        # Registered by string name (not the constant) per Otto's lazy-loading
        # form: Otto matches handlers on error.class.name, so this is harmless in
        # builds where the billing app — and thus Billing::PlanCacheMissError —
        # is never loaded (the error can't be raised there). log_level :error
        # keeps the fail-closed design's ops visibility intact.
        router.register_error_handler('Billing::PlanCacheMissError', status: 503, log_level: :error) do |error, req|
          with_error_correlation({
            error: 'Plan catalog is temporarily unavailable. Please try again shortly.',
            error_type: 'PlanCatalogUnavailable',
          }, req, error)
        end

        # Stripe circuit breaker open (Billing::CircuitOpenError) is the sibling
        # "backend temporarily can't serve" case: the breaker trips after
        # consecutive Stripe failures and fails fast to let the upstream recover.
        # Like the catalog miss above it is a known backend condition, not a
        # crash, so map it to 503 rather than letting it surface as a 500.
        #
        # Forward-looking, not a fix for an observed 500: today the breaker only
        # wraps the catalog Pull, whose callers (CLI, boot, webhook handler that
        # rescues it, scheduled jobs) are off the synchronous HTTP edge, so this
        # error cannot currently reach an Otto-handled request. The customer
        # facing billing endpoints call Stripe directly and already handle outages
        # via their own Stripe::StripeError rescues. This registration only fires
        # if a synchronous endpoint later routes a Stripe call through the breaker.
        #
        # Drop the error's message — it carries the internal failure count
        # ("...(7 failures)...") — and never name the upstream provider. Surface
        # retry_after in the body (Otto error handlers return a body hash only and
        # cannot set a Retry-After response header). log_level :warn, not :error:
        # this is a transient, self-healing protective state, unlike the catalog
        # miss which signals an operator-actionable config/sync problem. Registered
        # by string name per Otto's lazy-loading form (harmless when billing is not
        # loaded — the error can't be raised there).
        router.register_error_handler('Billing::CircuitOpenError', status: 503, log_level: :warn) do |error, req|
          body               = {
            error: 'The billing service is temporarily unavailable. Please try again shortly.',
            error_type: 'BillingServiceUnavailable',
          }
          body[:retry_after] = error.retry_after if error.retry_after
          with_error_correlation(body, req, error)
        end

        # Give the router the same trusted-proxy list as the outer IP-privacy
        # middleware. Done here (not in each build_router) so no Otto app can
        # land with an inconsistent trust list. Placed before the debug-only
        # request-logging hook below so it runs in production too.
        configure_otto_trusted_proxies(router)

        return unless Onetime.debug?

        router.on_request_complete do |req, res, duration|
          # Use HTTP logger for request lifecycle events
          logger = Onetime.get_logger('HTTP')

          # Extract auth context if available
          user_id         = req.env['otto.user']&.[](:id)
          strategy_result = req.env['otto.strategy_result']
          auth_strategy   = strategy_result&.strategy_name

          logger.trace 'Request completed',
            {
              method: req.request_method,
              path: req.path,
              status: res.status,
              duration: duration / 1_000_000.0,  # Convert microseconds to seconds for SemanticLogger
              user_id: user_id,
              auth_strategy: auth_strategy,
              ip: req.ip,
              user_agent: req.user_agent&.slice(0, 100),
            }
        end
      end

      # Mirror the trusted-proxy list onto the Otto router's own security
      # config so req.client_ipaddress and req.secure? agree with Rack's
      # request.ip about which hops to trust. No-op unless
      # site.network.trusted_proxy is enabled (same gate as the outer
      # IPPrivacyMiddleware via MiddlewareStack.ip_privacy_security_config).
      #
      # Defense-in-depth, not the primary path: the outer middleware runs
      # first and has already rewritten REMOTE_ADDR to the resolved (masked)
      # client by the time the router sees a request. For public clients that
      # masked address is not a trusted proxy, so this list does not fire and
      # they still depend on the outer rewrite — this list keeps resolution
      # correct if that middleware is ever reordered or removed. It does change
      # the private-origin requests the outer middleware exempts from masking
      # (REMOTE_ADDR left private): the router now walks X-Forwarded-For and
      # honors X-Forwarded-Proto for those, instead of returning the proxy hop.
      #
      # @param router [Otto] The Otto router instance to configure
      # @return [void]
      def configure_otto_trusted_proxies(router)
        return unless Onetime::Application::MiddlewareStack.trusted_proxy_enabled?

        router.add_trusted_proxy(Onetime::Application::MiddlewareStack::PRIVATE_PROXY_RANGES)
      end

      private

      # Decorate a JSON error body for log correlation, and record the error
      # type so the request log can name what failed.
      #
      # ## Why this exists
      #
      # Otto mints its own per-error id (Otto::Core::ErrorHandler, SecureRandom.hex),
      # but that id is a poor support handle: it is only added to the response body
      # in development, and it is logged on the separate 'Otto' logger whose context
      # carries no request_id. So in production an API consumer's error payload holds
      # no id that appears in our request log, and even in development there is no
      # single log line linking the error to the request_id.
      #
      # The request_id (env['HTTP_X_REQUEST_ID'], set by Rack::RequestId and returned
      # in the x-request-id response header) is logged by RequestLogger for every
      # request. Echoing it into the error body gives consumers one correlation id we
      # can grep straight out of the request log. We also stash the error_type into
      # env so RequestLogger can record *what* failed next to the status, keyed to
      # that same id.
      #
      # Nil-safe: the error-handler unit specs invoke these blocks with req == nil.
      #
      # @param body [Hash] The JSON error body the handler is about to return
      # @param req [Rack::Request, Otto::Request, nil] The current request
      # @param error [Exception, nil] The error being handled; used only as the
      #   fallback source for error_type when the body omits it
      # @return [Hash] The body, with :request_id merged in when available
      def with_error_correlation(body, req, error = nil)
        return body unless req.respond_to?(:env) && req.env

        # Prefer the body's class-specific error_type; fall back to the exception
        # class name so the request log still names the failure for errors whose
        # to_h compacts error_type away (e.g. a FormError raised without one).
        # The body is left untouched — this fallback only feeds the request log.
        error_type = body[:error_type] || error&.class&.name&.to_s&.split('::')&.last
        req.env['otto.error_type'] = error_type if error_type

        request_id = req.env['HTTP_X_REQUEST_ID']
        request_id ? body.merge(request_id: request_id) : body
      end
    end
  end
end
