# lib/onetime/error_handler.rb
#
# frozen_string_literal: true

# lib/onetime/error_handler.rb
#
# Provides robust error handling for non-critical operations, particularly
# side-effects in authentication hooks. Errors are logged with context but
# don't interrupt the parent operation.
#
module Onetime
  module ErrorHandler
    extend Onetime::LoggerMethods

    # Executes a block and logs any errors without re-raising.
    # Useful for side-effects that shouldn't break critical operations.
    #
    # @param operation [String] Name of the operation for logging/tracking
    # @param context [Hash] Additional context to log (e.g., account_id: 123)
    # @yield Block to execute with error protection
    #
    # @example
    #   ErrorHandler.safe_execute('create_customer', account_id: 123) do
    #     Customer.create!(email: 'user@example.com')
    #   end
    #
    def self.safe_execute(operation, **context)
      yield
    rescue StandardError => ex
      log_error(operation, ex, context)
      track_error(operation) if trackable?
      capture_error(operation, ex, context) if sentry_available?
    end

    # Lua script for atomic INCR + EXPIRE (prevents race condition
    # where a crash between the two commands leaves a permanent key).
    TRACK_ERROR_LUA = <<~LUA
      local c = redis.call('INCR', KEYS[1])
      if tonumber(c) == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end
      return c
    LUA

    # TTL for error tracking keys: 7 days in seconds
    ERROR_TRACKING_TTL = 86_400 * 7

    class << self
      private

      # Logs error details with operation context
      def log_error(operation, ex, context)
        app_logger.error "error-handler: #{operation} failed",
          {
            exception: ex,
            operation: operation,
            **context,
          }
      end

      # Tracks error frequency in Redis for monitoring
      # Keeps daily counters for 7 days to identify patterns
      # Uses atomic Lua script to prevent race conditions between INCR and EXPIRE.
      def track_error(operation)
        return unless Familia.dbclient

        key = "errors:rodauth:#{operation}:#{Date.today.strftime('%Y%m%d')}"
        Familia.dbclient.eval(TRACK_ERROR_LUA, keys: [key], argv: [ERROR_TRACKING_TTL])
      rescue StandardError => ex
        # Don't let tracking errors break the error handler itself
        app_logger.error 'error-handler: Failed to track error',
          {
            exception: ex,
            operation: 'track_error',
          }
      end

      # Captures error in Sentry with context
      def capture_error(operation, ex, context)
        Sentry.capture_exception(ex) do |scope|
          scope.set_context('error_handler', { operation: operation, **context })
          scope.set_level(:warning)
          scope.set_tags(operation: operation, error_handler: true)
        end
      rescue StandardError => ex
        # Don't let Sentry errors break the error handler itself
        app_logger.error 'error-handler: Failed to capture in Sentry',
          {
            exception: ex,
            operation: 'capture_error',
          }
      end

      # Check if error tracking is available
      def trackable?
        !Familia.dbclient.nil?
      end

      # Check if Sentry is configured
      def sentry_available?
        defined?(Sentry) && Sentry.initialized?
      end
    end
  end
end
