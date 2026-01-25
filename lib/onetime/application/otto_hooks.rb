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

        # Register expected errors with status codes and log levels
        router.register_error_handler(Onetime::RecordNotFound, status: 404, log_level: :info)
        router.register_error_handler(Onetime::MissingSecret, status: 404, log_level: :info)
        # Form errors return 422 with error type and field info
        router.register_error_handler(Onetime::FormError, status: 422, log_level: :info) do |error, _req|
          error.to_h
        end
        router.register_error_handler(Onetime::Forbidden, status: 403, log_level: :warn)

        # Entitlement errors return 403 with upgrade path info
        # NOTE: Otto handles Content-Type header automatically; handler returns body hash only
        router.register_error_handler(Onetime::EntitlementRequired, status: 403, log_level: :info) do |error, _req|
          error.to_h
        end

        # Guest routes disabled errors return 403 with error code
        router.register_error_handler(Onetime::GuestRoutesDisabled, status: 403, log_level: :info) do |error, _req|
          error.to_h
        end

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
    end
  end
end
