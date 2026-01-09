# apps/web/billing/lib/stripe_circuit_breaker.rb
#
# frozen_string_literal: true

require_relative '../errors'

module Billing
  # StripeCircuitBreaker - Prevents cascade failures during Stripe API outages
  #
  # Implements the circuit breaker pattern with Redis-backed state for distributed
  # coordination across multiple workers/processes. Uses Familia for Redis storage.
  #
  # ## Circuit States
  #
  # - **Closed**: Normal operation, API calls proceed
  # - **Open**: API unavailable, calls fail fast with CircuitOpenError
  # - **Half-Open**: Testing if API recovered, allows single probe request
  #
  # ## State Transitions
  #
  #   closed --[N consecutive failures]--> open
  #   open   --[timeout expires]--------> half-open
  #   half-open --[success]--------------> closed
  #   half-open --[failure]--------------> open
  #
  # ## Usage
  #
  #   # Wrap Stripe API calls
  #   Billing::StripeCircuitBreaker.call do
  #     Stripe::Product.list(active: true)
  #   end
  #
  #   # Check status for health endpoints
  #   status = Billing::StripeCircuitBreaker.status
  #   # => { state: 'closed', failure_count: 0, last_failure_at: nil }
  #
  #   # Manual reset (admin/recovery)
  #   Billing::StripeCircuitBreaker.reset!
  #
  # ## Configuration
  #
  # Uses module-level constants for configuration. Adjust based on:
  # - Stripe SLA expectations (99.99% uptime)
  # - Application tolerance for latency vs. availability
  # - Webhook retry timing (Stripe retries for up to 3 days)
  #
  class StripeCircuitBreaker
    extend Onetime::LoggerMethods

    # Number of consecutive failures before opening circuit
    FAILURE_THRESHOLD = 5

    # Seconds to wait before attempting recovery (half-open state)
    RECOVERY_TIMEOUT = 60

    # Redis key prefix for circuit breaker state
    REDIS_KEY_PREFIX = 'billing:circuit_breaker:stripe'

    # Error types that should trip the circuit breaker
    # Excludes authentication errors (config issue, not outage)
    TRIPPABLE_ERRORS = [
      Stripe::APIConnectionError,
      Stripe::RateLimitError,
      Stripe::APIError,
    ].freeze

    class << self
      # Execute block with circuit breaker protection
      #
      # @yield Block containing Stripe API call(s)
      # @return Result of the block
      # @raise [Billing::CircuitOpenError] If circuit is open
      # @raise [Stripe::StripeError] If API call fails (after recording failure)
      #
      # @example
      #   products = Billing::StripeCircuitBreaker.call do
      #     Stripe::Product.list(active: true, limit: 100)
      #   end
      #
      def call(&)
        raise ArgumentError, 'Block required' unless block_given?

        check_circuit!
        execute_with_tracking(&)
      end

      # Get current circuit breaker status
      #
      # @return [Hash] Status hash with state, failure_count, timestamps
      #
      # @example
      #   Billing::StripeCircuitBreaker.status
      #   # => {
      #   #   state: 'closed',
      #   #   failure_count: 0,
      #   #   last_failure_at: nil,
      #   #   opened_at: nil,
      #   #   recovery_at: nil
      #   # }
      #
      def status
        state_data = load_state

        {
          state: determine_state(state_data),
          failure_count: state_data[:failure_count],
          last_failure_at: state_data[:last_failure_at],
          opened_at: state_data[:opened_at],
          recovery_at: state_data[:opened_at] ? state_data[:opened_at] + RECOVERY_TIMEOUT : nil,
        }
      end

      # Reset circuit breaker to closed state
      #
      # Use for manual recovery after confirming Stripe is available.
      # Logs the reset for audit trail.
      #
      # @return [Boolean] true if reset successful
      #
      def reset!
        billing_logger.info '[StripeCircuitBreaker] Manual reset requested'
        clear_state
        billing_logger.info '[StripeCircuitBreaker] Circuit reset to closed'
        true
      end

      # Check if circuit is currently open
      #
      # @return [Boolean] true if circuit is open (API calls blocked)
      #
      def open?
        determine_state(load_state) == 'open'
      end

      # Check if circuit is currently closed
      #
      # @return [Boolean] true if circuit is closed (normal operation)
      #
      def closed?
        determine_state(load_state) == 'closed'
      end

      # Check if circuit is in half-open state
      #
      # @return [Boolean] true if circuit is half-open (testing recovery)
      #
      def half_open?
        determine_state(load_state) == 'half-open'
      end

      private

      # Check circuit state and raise if open
      #
      # Transitions from open to half-open if recovery timeout has passed.
      #
      # @raise [Billing::CircuitOpenError] If circuit is open
      #
      def check_circuit!
        state_data    = load_state
        current_state = determine_state(state_data)

        case current_state
        when 'open'
          retry_after = calculate_retry_after(state_data[:opened_at])
          billing_logger.debug '[StripeCircuitBreaker] Circuit open, rejecting request', {
            retry_after: retry_after,
            failure_count: state_data[:failure_count],
          }
          raise CircuitOpenError.new(
            "Stripe circuit breaker is open (#{state_data[:failure_count]} failures). " \
            "Retry after #{retry_after}s.",
            retry_after: retry_after,
          )
        when 'half-open'
          billing_logger.info '[StripeCircuitBreaker] Half-open, allowing probe request'
        end
        # closed state: proceed normally
      end

      # Execute block and track success/failure
      #
      # @yield Block to execute
      # @return Result of block
      # @raise [Stripe::StripeError] Re-raises after recording failure
      #
      def execute_with_tracking
        result = yield
        record_success
        result
      rescue *TRIPPABLE_ERRORS => ex
        record_failure(ex)
        raise
      end

      # Record successful API call
      #
      # Resets failure count and closes circuit.
      #
      def record_success
        previous_state = load_state
        was_half_open  = determine_state(previous_state) == 'half-open'

        clear_state

        return unless was_half_open

        billing_logger.info '[StripeCircuitBreaker] Recovery successful, circuit closed', {
          previous_failures: previous_state[:failure_count],
        }
      end

      # Record API failure
      #
      # Increments failure count atomically and opens circuit if threshold reached.
      # Uses Redis HINCRBY for atomic increment to prevent race conditions in
      # distributed environments where multiple processes may record failures
      # simultaneously.
      #
      # @param error [Exception] The error that occurred
      #
      def record_failure(error)
        redis = Familia.dbclient
        now   = Time.now.to_i

        # Atomic increment - prevents race conditions between load/increment/save
        new_count = redis.hincrby(redis_key, 'failure_count', 1)
        redis.hset(redis_key, 'last_failure_at', now.to_s)
        redis.expire(redis_key, 3600) # Auto-expire after 1 hour

        if new_count >= FAILURE_THRESHOLD
          # Open circuit - use HSETNX to only set opened_at once (first to reach threshold wins)
          redis.hsetnx(redis_key, 'opened_at', now.to_s)
          billing_logger.warn '[StripeCircuitBreaker] Circuit OPENED', {
            failure_count: new_count,
            threshold: FAILURE_THRESHOLD,
            error_class: error.class.name,
            error_message: error.message,
          }
        else
          billing_logger.warn '[StripeCircuitBreaker] Failure recorded', {
            failure_count: new_count,
            threshold: FAILURE_THRESHOLD,
            error_class: error.class.name,
          }
        end
      end

      # Determine current state based on stored data
      #
      # @param state_data [Hash] Loaded state from Redis
      # @return [String] 'closed', 'open', or 'half-open'
      #
      def determine_state(state_data)
        return 'closed' if state_data[:failure_count] < FAILURE_THRESHOLD
        return 'closed' if state_data[:opened_at].nil?

        # Check if recovery timeout has passed
        if Time.now.to_i >= state_data[:opened_at] + RECOVERY_TIMEOUT
          'half-open'
        else
          'open'
        end
      end

      # Calculate seconds until circuit may transition to half-open
      #
      # @param opened_at [Integer] Unix timestamp when circuit opened
      # @return [Integer] Seconds until retry allowed
      #
      def calculate_retry_after(opened_at)
        return 0 unless opened_at

        recovery_at = opened_at + RECOVERY_TIMEOUT
        [recovery_at - Time.now.to_i, 0].max
      end

      # Load circuit state from Redis
      #
      # @return [Hash] State data with :failure_count, :last_failure_at, :opened_at
      #
      def load_state
        redis = Familia.dbclient
        data  = redis.hgetall(redis_key)

        {
          failure_count: data['failure_count'].to_i,
          last_failure_at: data['last_failure_at']&.to_i,
          opened_at: data['opened_at']&.to_i,
        }
      end

      # Save circuit state to Redis
      #
      # Sets TTL to auto-expire state after extended period (prevents stale data).
      #
      # @param failure_count [Integer] Current failure count
      # @param last_failure_at [Integer] Unix timestamp of last failure
      # @param opened_at [Integer, nil] Unix timestamp when circuit opened
      #
      def save_state(failure_count:, last_failure_at:, opened_at:)
        redis             = Familia.dbclient
        data              = {
          'failure_count' => failure_count.to_s,
          'last_failure_at' => last_failure_at.to_s,
        }
        data['opened_at'] = opened_at.to_s if opened_at

        redis.multi do |multi|
          multi.hset(redis_key, data)
          # Auto-expire after 1 hour to prevent stale state
          multi.expire(redis_key, 3600)
        end
      end

      # Clear circuit state (reset to closed)
      #
      def clear_state
        Familia.dbclient.del(redis_key)
      end

      # Redis key for circuit breaker state
      #
      # @return [String] Redis key
      #
      def redis_key
        REDIS_KEY_PREFIX
      end
    end
  end
end
