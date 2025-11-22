# frozen_string_literal: true

require 'stripe'
require 'securerandom'

module Billing
  # StripeClient - Wrapper for Stripe API calls with reliability features
  #
  # Provides centralized Stripe API interaction with:
  # - Automatic retry with exponential backoff for transient failures
  # - Idempotency key generation to prevent duplicate charges
  # - Request timeouts to prevent hanging operations
  # - Consistent error handling and logging
  # - Rate limit handling with appropriate backoff
  #
  # ## Usage
  #
  #   client = Billing::StripeClient.new
  #
  #   # Automatic idempotency for creates
  #   customer = client.create(Stripe::Customer, email: 'user@example.com')
  #
  #   # Updates with retry
  #   client.update(Stripe::Customer, customer_id, metadata: { foo: 'bar' })
  #
  #   # Retrieves with retry
  #   subscription = client.retrieve(Stripe::Subscription, 'sub_123')
  #
  class StripeClient
    include Onetime::LoggerMethods

    module StripeTestCards
      SUCCESS = '4242424242424242'
      DECLINED = '4000000000000002'
      INSUFFICIENT_FUNDS = '4000000000009995'
      EXPIRED = '4000000000000069'
      PROCESSING_ERROR = '4000000000000119'
    end

    # Maximum number of retry attempts for failed requests
    MAX_RETRIES = 3

    # Retry delays for network errors (linear backoff: 2s, 4s, 6s)
    NETWORK_RETRY_BASE_DELAY = 2 # seconds

    # Retry delays for rate limits (exponential backoff: 4s, 8s, 16s)
    RATE_LIMIT_RETRY_BASE_DELAY = 2 # seconds

    # Maximum retry delay to cap exponential backoff
    MAX_RETRY_DELAY = 30 # seconds

    # Request timeout to prevent hanging operations
    REQUEST_TIMEOUT = 30 # seconds

    # Retryable error classes (network and rate limit errors)
    RETRYABLE_ERRORS = [
      Stripe::APIConnectionError,
      Stripe::RateLimitError,
    ].freeze

    def initialize(api_key: nil)
      @api_key = api_key || Onetime.billing_config.stripe_key
      configure_stripe
    end

    # Create a Stripe resource with automatic idempotency
    #
    # Generates an idempotency key automatically unless provided.
    # This prevents duplicate resource creation if request is retried.
    #
    # @param resource_class [Class] Stripe resource class (e.g., Stripe::Customer)
    # @param params [Hash] Resource creation parameters
    # @param idempotency_key [String, nil] Optional explicit idempotency key
    # @return [Stripe::StripeObject] Created resource
    # @raise [Stripe::StripeError] If creation fails after retries
    #
    # @example
    #   client.create(Stripe::Customer, email: 'user@example.com', name: 'John')
    #
    def create(resource_class, params = {}, idempotency_key: nil)
      key = idempotency_key || generate_idempotency_key

      billing_logger.debug "[StripeClient.create] Creating #{resource_class}", {
        params: params.except(:card, :source), # Don't log sensitive data
        idempotency_key: key
      }

      with_retry do
        resource_class.create(params, { idempotency_key: key })
      end
    end

    # Update a Stripe resource
    #
    # @param resource_class [Class] Stripe resource class
    # @param id [String] Resource ID
    # @param params [Hash] Update parameters
    # @return [Stripe::StripeObject] Updated resource
    # @raise [Stripe::StripeError] If update fails after retries
    #
    # @example
    #   client.update(Stripe::Customer, 'cus_123', metadata: { foo: 'bar' })
    #
    def update(resource_class, id, params = {})
      billing_logger.debug "[StripeClient.update] Updating #{resource_class}", {
        id: id,
        params: params.except(:card, :source)
      }

      with_retry do
        resource_class.update(id, params)
      end
    end

    # Retrieve a Stripe resource by ID
    #
    # @param resource_class [Class] Stripe resource class
    # @param id [String] Resource ID
    # @param expand [Array<String>] Optional fields to expand
    # @return [Stripe::StripeObject] Retrieved resource
    # @raise [Stripe::StripeError] If retrieval fails after retries
    #
    # @example
    #   client.retrieve(Stripe::Subscription, 'sub_123', expand: ['customer'])
    #
    def retrieve(resource_class, id, expand: nil)
      params = {}
      params[:expand] = expand if expand

      with_retry do
        resource_class.retrieve(id, params)
      end
    end

    # List Stripe resources
    #
    # @param resource_class [Class] Stripe resource class
    # @param params [Hash] List parameters (limit, starting_after, etc.)
    # @return [Stripe::ListObject] List of resources
    # @raise [Stripe::StripeError] If list fails after retries
    #
    # @example
    #   client.list(Stripe::Customer, limit: 100)
    #
    def list(resource_class, params = {})
      with_retry do
        resource_class.list(params)
      end
    end

    # Delete/cancel a Stripe resource
    #
    # Some resources use 'cancel' instead of 'delete' (e.g., Subscription).
    # This method handles both cases appropriately.
    #
    # @param resource_class [Class] Stripe resource class
    # @param id [String] Resource ID
    # @return [Stripe::StripeObject] Deleted/canceled resource
    # @raise [Stripe::StripeError] If deletion fails after retries
    #
    # @example
    #   client.delete(Stripe::Subscription, 'sub_123')
    #
    def delete(resource_class, id)
      billing_logger.debug "[StripeClient.delete] Deleting #{resource_class}", {
        id: id
      }

      with_retry do
        # Subscriptions use 'cancel' instead of 'delete'
        if resource_class == Stripe::Subscription
          resource_class.cancel(id)
        else
          resource_class.delete(id)
        end
      end
    end

    private

    # Configure Stripe SDK with API key and timeouts
    #
    # Sets request timeouts to prevent hanging operations.
    # Disables Stripe's built-in retry logic to maintain our own control.
    #
    def configure_stripe
      Stripe.api_key = @api_key
      Stripe.open_timeout = REQUEST_TIMEOUT
      Stripe.read_timeout = REQUEST_TIMEOUT

      # Disable Stripe's automatic retries - we handle retries ourselves
      # This gives us better control over retry logic and logging
      Stripe.max_network_retries = 0
    end

    # Generate idempotency key for request deduplication
    #
    # Format: {timestamp}-{uuid}
    # - Timestamp allows sorting and debugging
    # - UUID ensures global uniqueness
    #
    # @return [String] Idempotency key
    #
    # @example
    #   "1637012345-550e8400-e29b-41d4-a716-446655440000"
    #
    def generate_idempotency_key
      "#{Time.now.to_i}-#{SecureRandom.uuid}"
    end

    # Execute block with automatic retry on transient failures
    #
    # Implements differentiated retry strategies:
    # - Network errors: Linear backoff (2s, 4s, 6s)
    # - Rate limits: Exponential backoff (4s, 8s, 16s)
    # - Other Stripe errors: No retry (fail fast)
    #
    # @yield Block to execute with retry protection
    # @return Result of the yielded block
    # @raise [Stripe::StripeError] If all retries exhausted or non-retryable error
    #
    def with_retry
      retries = 0
      begin
        yield
      rescue Stripe::APIConnectionError => e
        retries += 1
        if retries <= MAX_RETRIES
          # Linear backoff for network errors
          delay = NETWORK_RETRY_BASE_DELAY * retries
          delay = [delay, MAX_RETRY_DELAY].min

          billing_logger.warn "[StripeClient] Network error, retrying", {
            attempt: retries,
            max_retries: MAX_RETRIES,
            delay: delay,
            error: e.message
          }

          sleep(delay)
          retry
        end

        billing_logger.error "[StripeClient] Network error exhausted retries", {
          attempts: retries,
          error: e.message
        }
        raise
      rescue Stripe::RateLimitError => e
        retries += 1
        if retries <= MAX_RETRIES
          # Exponential backoff for rate limits
          delay = RATE_LIMIT_RETRY_BASE_DELAY * (2 ** retries)
          delay = [delay, MAX_RETRY_DELAY].min

          billing_logger.warn "[StripeClient] Rate limited, backing off", {
            attempt: retries,
            max_retries: MAX_RETRIES,
            delay: delay,
            error: e.message
          }

          sleep(delay)
          retry
        end

        billing_logger.error "[StripeClient] Rate limit exhausted retries", {
          attempts: retries,
          error: e.message
        }
        raise
      rescue Stripe::StripeError => e
        # Don't retry other Stripe errors (invalid requests, auth failures, etc.)
        # These are not transient and retrying won't help
        billing_logger.error "[StripeClient] Non-retryable Stripe error", {
          error_class: e.class.name,
          error: e.message
        }
        raise
      end
    end
  end
end
