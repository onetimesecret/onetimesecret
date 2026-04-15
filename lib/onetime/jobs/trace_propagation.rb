# lib/onetime/jobs/trace_propagation.rb
#
# frozen_string_literal: true

module Onetime
  module Jobs
    # Sentry distributed tracing utilities for RabbitMQ message propagation.
    #
    # Enables trace context to flow from web requests to background workers,
    # linking errors and performance data in Sentry.
    #
    # Publisher side (web request):
    #   headers = TracePropagation.extract_trace_headers
    #   channel.publish(payload, headers: headers.merge(other_headers))
    #
    # Worker side (background job):
    #   trace_headers = TracePropagation.parse_trace_headers(metadata)
    #   TracePropagation.continue_trace(trace_headers, name: 'queue.process') do
    #     # process message - errors will be linked to originating request
    #   end
    #
    module TracePropagation
      # Standard Sentry trace header names
      SENTRY_TRACE_HEADER = 'sentry-trace'
      BAGGAGE_HEADER      = 'baggage'

      class << self
        # Extract current Sentry trace headers for outgoing messages.
        #
        # Should be called from the request thread before any async fallback,
        # as new threads lose Sentry context.
        #
        # @return [Hash<String, String>] Trace headers to include in message,
        #   or empty hash if Sentry not configured or no active trace
        def extract_trace_headers
          return {} unless sentry_available?
          return {} unless Sentry.get_current_scope&.get_span

          Sentry.get_trace_propagation_headers || {}
        rescue StandardError => ex
          # Don't let tracing failures break message publishing
          log_trace_error('extract_trace_headers', ex)
          {}
        end

        # Parse trace headers from incoming message metadata.
        #
        # Handles nil gracefully for backwards compatibility with messages
        # published before trace propagation was implemented.
        #
        # @param metadata [Bunny::MessageProperties, nil] AMQP message properties
        # @return [Hash<String, String>] Trace headers or empty hash
        def parse_trace_headers(metadata)
          return {} unless metadata

          headers = metadata.headers
          return {} unless headers.is_a?(Hash)

          result                      = {}
          result[SENTRY_TRACE_HEADER] = headers[SENTRY_TRACE_HEADER] if headers[SENTRY_TRACE_HEADER]
          result[BAGGAGE_HEADER]      = headers[BAGGAGE_HEADER] if headers[BAGGAGE_HEADER]
          result
        rescue StandardError => ex
          log_trace_error('parse_trace_headers', ex)
          {}
        end

        # Continue a trace from parsed headers and wrap processing in a transaction.
        #
        # If no trace headers are present, creates a new root transaction.
        # If Sentry is not available, yields without creating a transaction.
        #
        # Uses Sentry.with_scope to ensure the transaction is set on a LOCAL scope,
        # preventing span leakage in multi-threaded workers. Sets status to 'ok'
        # before yielding to handle non-local returns (e.g., `return ack!`).
        #
        # @param trace_headers [Hash<String, String>] Headers from parse_trace_headers
        # @param name [String] Transaction name (e.g., 'queue.process')
        # @param op [String] Span operation (e.g., 'queue.process')
        # @yield Block to execute within the transaction
        # @return Result of the block
        def continue_trace(trace_headers, name:, op: 'queue.process')
          unless sentry_available?
            return yield if block_given?

            return nil
          end

          Sentry.with_scope do |scope|
            transaction = Sentry.continue_trace(trace_headers, name: name, op: op)

            unless transaction
              return yield if block_given?

              return nil
            end

            # Set transaction on LOCAL scope (not global)
            scope.set_span(transaction)

            # Default to 'ok' to handle non-local returns (e.g. 'return' in block)
            transaction.set_status('ok')

            begin
              yield if block_given?
            rescue StandardError
              transaction.set_status('internal_error')
              raise
            ensure
              transaction.finish
            end
          end
        end

        private

        # Check if Sentry is available and initialized
        # @return [Boolean]
        def sentry_available?
          defined?(Sentry) && Sentry.initialized?
        end

        # Log trace-related errors without breaking the main flow
        # @param operation [String] Which operation failed
        # @param error [StandardError] The error that occurred
        def log_trace_error(operation, error)
          return unless defined?(OT)

          OT.ld "[trace_propagation] #{operation} failed: #{error.class} - #{error.message}"
        end
      end
    end
  end
end
