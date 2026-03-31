# lib/onetime/utils/retry_helper.rb
#
# frozen_string_literal: true

module Onetime
  module Utils
    # RetryHelper provides retry logic with exponential backoff and jitter.
    #
    # Can be used as a mixin (include/extend) or standalone via module methods.
    #
    # Example as mixin:
    #   class MyWorker
    #     include Onetime::Utils::RetryHelper
    #
    #     def perform
    #       with_retry(max_retries: 3) { external_api_call }
    #     end
    #   end
    #
    # Example standalone:
    #   Onetime::Utils::RetryHelper.with_retry(max_retries: 2) do
    #     risky_operation
    #   end
    #
    module RetryHelper
      extend self

      # Default logger name for standalone usage
      DEFAULT_LOGGER_NAME = 'RetryHelper'

      # Execute a block with retry logic and exponential backoff.
      #
      # @param max_retries [Integer] Maximum retry attempts (default: 3)
      # @param base_delay [Float] Base delay in seconds (default: 1.0)
      # @param retriable [Proc, nil] Optional predicate to check if an error
      #   should be retried. Receives the exception; returns true to retry,
      #   false to re-raise immediately. Defaults to retrying all StandardError.
      # @param logger [#info, #error, nil] Optional logger for retry messages.
      #   If nil, uses Onetime.get_logger when available.
      # @param context [String, nil] Optional context string for log messages
      #   (e.g., "DNS lookup", "API call")
      #
      # @yield The block to execute with retry protection
      # @return [Object] The return value of the block
      # @raise [StandardError] Re-raises the last exception after max retries
      #
      # Backoff formula: base_delay * 2^(retry_number - 1) + jitter
      # Jitter: random value up to 30% of the computed delay
      #
      # Example delays with base_delay=1.0:
      #   Retry 1: ~1.0-1.3s
      #   Retry 2: ~2.0-2.6s
      #   Retry 3: ~4.0-5.2s
      #
      def with_retry(max_retries: 3, base_delay: 1.0, retriable: nil, logger: nil, context: nil)
        retries = 0
        log     = resolve_logger(logger)
        ctx     = context ? "[#{context}] " : ''

        begin
          yield
        rescue StandardError => ex
          # Skip retries if the caller says this error is not retriable
          unless retriable.nil? || retriable.call(ex)
            log&.error("#{ctx}Non-retriable error, skipping retries: #{ex.message}")
            raise
          end

          retries += 1
          if retries <= max_retries
            delay = compute_delay(base_delay, retries)
            log&.info 'Retry attempt',
              attempt: retries,
              max: max_retries,
              delay: format('%.2f', delay),
              context: context,
              error_class: ex.class.name,
              error_message: ex.message
            sleep(delay)
            retry
          else
            log&.error 'Max retries exceeded',
              max: max_retries,
              context: context,
              error_class: ex.class.name,
              error_message: ex.message
            raise
          end
        end
      end

      # Compute delay with exponential backoff and jitter.
      #
      # @param base_delay [Float] Base delay in seconds
      # @param retry_number [Integer] Current retry attempt (1-based)
      # @return [Float] Computed delay with jitter
      #
      def compute_delay(base_delay, retry_number)
        delay  = base_delay * (2**(retry_number - 1))
        jitter = rand * delay * 0.3
        delay + jitter
      end

      private

      def resolve_logger(provided_logger)
        return provided_logger if provided_logger

        if defined?(Onetime) && Onetime.respond_to?(:get_logger)
          Onetime.get_logger(DEFAULT_LOGGER_NAME)
        end
      end
    end
  end
end
