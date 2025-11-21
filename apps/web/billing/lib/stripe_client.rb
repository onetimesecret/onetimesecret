# frozen_string_literal: true

require 'stripe'
require 'securerandom'

module Billing
  # Stripe API Client with retry logic and idempotency support
  #
  # Wraps Stripe SDK calls with:
  # - Automatic retry with exponential backoff
  # - Idempotency key generation and management
  # - Comprehensive error logging
  # - Request timeout configuration
  #
  # ## Usage
  #
  #   client = Billing::StripeClient.new
  #
  #   # Create with automatic idempotency key
  #   customer = client.create(Stripe::Customer, {
  #     email: 'user@example.com',
  #     name: 'John Doe'
  #   })
  #
  #   # Update with retries
  #   subscription = client.update(Stripe::Subscription, subscription_id, {
  #     cancel_at_period_end: true
  #   })
  #
  class StripeClient
    include Onetime::LoggerMethods

    # Maximum number of retry attempts for failed requests
    MAX_RETRIES = 3

    # Initial delay between retries (seconds)
    INITIAL_RETRY_DELAY = 1.0

    # Maximum delay between retries (seconds)
    MAX_RETRY_DELAY = 10.0

    # Request timeout in seconds
    REQUEST_TIMEOUT = 30

    # Network-related errors that should be retried
    RETRYABLE_ERRORS = [
      Stripe::APIConnectionError,
      Stripe::RateLimitError,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ECONNREFUSED,
      Errno::ECONNRESET,
      Errno::ETIMEDOUT,
    ].freeze

    def initialize
      configure_stripe
    end

    # Create a Stripe resource with idempotency key
    #
    # @param klass [Class] Stripe resource class (e.g., Stripe::Customer)
    # @param params [Hash] Creation parameters
    # @param idempotency_key [String, nil] Custom idempotency key (auto-generated if nil)
    # @return [Object] Created Stripe resource
    def create(klass, params, idempotency_key: nil)
      idempotency_key ||= generate_idempotency_key

      with_retry do
        options = { idempotency_key: idempotency_key }
        klass.create(params, options)
      end
    end

    # Update a Stripe resource
    #
    # @param klass [Class] Stripe resource class
    # @param id [String] Resource ID
    # @param params [Hash] Update parameters
    # @return [Object] Updated Stripe resource
    def update(klass, id, params)
      with_retry do
        klass.update(id, params)
      end
    end

    # Retrieve a Stripe resource
    #
    # @param klass [Class] Stripe resource class
    # @param id [String] Resource ID
    # @param options [Hash] Additional options (e.g., expand)
    # @return [Object] Retrieved Stripe resource
    def retrieve(klass, id, options = {})
      with_retry do
        klass.retrieve(id, options)
      end
    end

    # List Stripe resources
    #
    # @param klass [Class] Stripe resource class
    # @param params [Hash] Query parameters
    # @return [Stripe::ListObject] List of resources
    def list(klass, params = {})
      with_retry do
        klass.list(params)
      end
    end

    # Delete/cancel a Stripe resource
    #
    # @param klass [Class] Stripe resource class
    # @param id [String] Resource ID
    # @return [Object] Deleted resource
    def delete(klass, id)
      with_retry do
        if klass.respond_to?(:cancel)
          klass.cancel(id)
        else
          klass.delete(id)
        end
      end
    end

    private

    # Configure Stripe SDK
    def configure_stripe
      Stripe.api_key = Onetime.billing_config.stripe_key
      Stripe.max_network_retries = 0 # We handle retries ourselves
      Stripe.open_timeout = REQUEST_TIMEOUT
      Stripe.read_timeout = REQUEST_TIMEOUT
    end

    # Generate unique idempotency key
    #
    # Format: timestamp-uuid to ensure uniqueness and aid debugging
    #
    # @return [String] Idempotency key
    def generate_idempotency_key
      timestamp = Time.now.to_i
      uuid = SecureRandom.uuid
      "#{timestamp}-#{uuid}"
    end

    # Execute block with automatic retry on transient failures
    #
    # @yield Block to execute
    # @return [Object] Result of block execution
    def with_retry
      attempt = 0
      delay = INITIAL_RETRY_DELAY

      begin
        attempt += 1
        yield
      rescue *RETRYABLE_ERRORS => ex
        if attempt < MAX_RETRIES
          billing_logger.warn 'Stripe API request failed, retrying', {
            attempt: attempt,
            max_retries: MAX_RETRIES,
            delay: delay,
            error: ex.class.name,
            message: ex.message,
          }

          sleep(delay)
          delay = [delay * 2, MAX_RETRY_DELAY].min
          retry
        else
          billing_logger.error 'Stripe API request failed after retries', {
            attempts: attempt,
            error: ex.class.name,
            message: ex.message,
          }
          raise
        end
      rescue Stripe::StripeError => ex
        billing_logger.error 'Stripe API error', {
          error: ex.class.name,
          message: ex.message,
          code: ex.code,
          http_status: ex.http_status,
        }
        raise
      end
    end
  end
end
