# apps/web/billing/operations/catalog/stripe_retry.rb
#
# frozen_string_literal: true

module Billing
  module Operations
    module Catalog
      # Retry wrapper for Stripe API calls with backoff strategies.
      #
      # Extracted from CLI::BillingHelpers for use in operations layer.
      # Uses linear backoff for connection errors, exponential for rate limits.
      #
      module StripeRetry
        extend self

        MAX_RETRIES = 3
        BASE_DELAY  = 2

        # Execute Stripe API call with automatic retry
        #
        # @param max_retries [Integer] Maximum retry attempts
        # @yield Block containing Stripe API call
        # @return Result of the yielded block
        # @raise [Stripe::StripeError] If all retries exhausted
        def with_retry(max_retries: MAX_RETRIES)
          retries = 0
          begin
            yield
          rescue Stripe::APIConnectionError
            retries += 1
            if retries <= max_retries
              delay = BASE_DELAY * retries
              OT.lw "Stripe connection error, retrying in #{delay}s (#{retries}/#{max_retries})"
              sleep(delay)
              retry
            end
            raise
          rescue Stripe::RateLimitError
            retries += 1
            if retries <= max_retries
              delay = BASE_DELAY * (2**retries)
              OT.lw "Stripe rate limit, backing off #{delay}s (#{retries}/#{max_retries})"
              sleep(delay)
              retry
            end
            raise
          end
        end
      end
    end
  end
end
