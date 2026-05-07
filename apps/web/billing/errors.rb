# apps/web/billing/errors.rb
#
# frozen_string_literal: true

module Billing
  # General billing operations problem - inherits from Onetime::Problem
  # for consistency with the application's error hierarchy.
  class OpsProblem < Onetime::Problem
  end

  # Raised when an operation is explicitly forbidden by business rules.
  # For example, attempting to update an existing Stripe price (which
  # is immutable in Stripe's API design).
  #
  # Uses a custom exit code (87) to distinguish from general errors
  # when running CLI commands.
  class ForbiddenOperation < RuntimeError
    EXIT_CODE = 87

    def exit_code
      EXIT_CODE
    end
  end

  # PlanCacheMissError - Raised when a plan_id cannot be resolved
  #
  # This error indicates a billing integrity issue where:
  # - The plan_id is not in Redis cache AND
  # - The plan_id is not in billing.yaml config
  #
  # Fail-closed behavior: We raise rather than silently degrading to free tier,
  # which could mask misconfiguration or catalog sync issues.
  #
  class PlanCacheMissError < OpsProblem
    attr_reader :plan_id, :context, :resource

    def initialize(message = nil, plan_id: nil, context: nil, resource: nil)
      @plan_id  = plan_id
      @context  = context
      @resource = resource
      message ||= "Plan not found in cache or config: #{plan_id}"
      super(message)
    end
  end

  # Raised when the Stripe circuit breaker is open.
  #
  # The circuit breaker opens after consecutive Stripe API failures to prevent
  # cascade failures and allow Stripe time to recover. Callers should catch
  # this error and either fail gracefully or use cached data.
  #
  # @example Handling circuit open state
  #   begin
  #     Billing::StripeCircuitBreaker.call { Stripe::Product.list }
  #   rescue Billing::CircuitOpenError => e
  #     # Use cached catalog data or return error to user
  #     OT.logger.warn "Circuit open: #{e.message}"
  #   end
  #
  class CircuitOpenError < OpsProblem
    attr_reader :retry_after

    # @param message [String] Error description
    # @param retry_after [Integer, nil] Seconds until circuit may close (half-open timeout)
    def initialize(message = 'Stripe circuit breaker is open', retry_after: nil)
      @retry_after = retry_after
      super(message)
    end
  end
end
