# apps/web/billing/lib/plan_resolver.rb
#
# frozen_string_literal: true

require_relative '../models/plan'

module Billing
  # PlanResolver - Maps URL parameters to checkout parameters
  #
  # Resolves plan selection from pricing page URLs to billing checkout params.
  # Handles the conversion from user-facing URL structure to internal billing format.
  #
  # ## URL Structure
  #
  # Pricing page URLs follow the pattern: /pricing/:product/:interval
  # Examples:
  #   - /pricing/identity_plus_v1/monthly
  #   - /pricing/team_plus_v1/yearly
  #
  # The product param maps to a plan_id base (without interval suffix).
  # The interval param is either 'monthly' or 'yearly'.
  #
  # ## Checkout Parameters
  #
  # The checkout endpoint expects:
  #   - tier: Plan tier (e.g., 'identity', 'team')
  #   - billing_cycle: 'monthly' or 'yearly'
  #
  # This resolver validates the params and returns the correct checkout values.
  #
  # ## Usage
  #
  #   # Resolve plan from URL params
  #   result = Billing::PlanResolver.resolve(
  #     product: 'identity_plus_v1',
  #     interval: 'monthly'
  #   )
  #
  #   if result.success?
  #     # result.plan_id => 'identity_plus_v1_monthly'
  #     # result.tier => 'identity'
  #     # result.billing_cycle => 'monthly'
  #     # result.checkout_url => '/billing/api/org/:extid/checkout'
  #   else
  #     # result.error => 'Plan not found'
  #   end
  #
  module PlanResolver
    extend self

    VALID_INTERVALS = %w[monthly yearly].freeze

    # Result struct for plan resolution
    #
    # @attr success [Boolean] Whether resolution succeeded
    # @attr plan_id [String, nil] Full plan ID with interval suffix
    # @attr tier [String, nil] Plan tier from catalog
    # @attr billing_cycle [String, nil] Billing cycle (monthly/yearly)
    # @attr plan [Billing::Plan, nil] The resolved plan object
    # @attr error [String, nil] Error message if resolution failed
    Result = Struct.new(
      :success,
      :plan_id,
      :tier,
      :billing_cycle,
      :plan,
      :error,
      keyword_init: true,
    ) do
      def success?
        success == true
      end

      def failed?
        !success?
      end

      # Generate checkout URL for an organization
      #
      # @param org_extid [String] Organization external ID
      # @return [String, nil] Checkout URL or nil if resolution failed
      def checkout_url(org_extid)
        return nil unless success?

        "/billing/api/org/#{org_extid}/checkout"
      end

      # Generate checkout params for the billing API
      #
      # @return [Hash, nil] Checkout params or nil if resolution failed
      def checkout_params
        return nil unless success?

        {
          tier: tier,
          billing_cycle: billing_cycle,
        }
      end
    end

    # Resolve plan from URL parameters
    #
    # Takes the product and interval from pricing page URLs and resolves
    # them to checkout parameters by looking up the plan in the catalog.
    #
    # @param product [String] Product identifier (e.g., 'identity_plus_v1')
    # @param interval [String] Billing interval ('monthly' or 'yearly')
    # @return [Result] Resolution result with plan details or error
    #
    def resolve(product:, interval:)
      # Validate inputs
      return error_result('Missing product') if product.nil? || product.to_s.strip.empty?
      return error_result('Missing interval') if interval.nil? || interval.to_s.strip.empty?

      # Normalize interval
      normalized_interval = normalize_interval(interval)
      unless normalized_interval
        return error_result("Invalid interval: #{interval}. Must be 'monthly' or 'yearly'")
      end

      # Construct plan_id: product + interval suffix
      # e.g., 'identity_plus_v1' + 'monthly' => 'identity_plus_v1_monthly'
      plan_id = "#{product}_#{normalized_interval}"

      # Look up plan in catalog
      plan = Billing::Plan.load(plan_id)
      unless plan&.exists?
        # Try config fallback for dev/test environments
        config_plan = Billing::Plan.load_from_config(plan_id)
        if config_plan
          return Result.new(
            success: true,
            plan_id: plan_id,
            tier: config_plan[:tier],
            billing_cycle: normalized_interval,
            plan: nil,
            error: nil,
          )
        end

        return error_result("Plan not found: #{plan_id}")
      end

      Result.new(
        success: true,
        plan_id: plan.plan_id,
        tier: plan.tier,
        billing_cycle: normalized_interval,
        plan: plan,
        error: nil,
      )
    end

    # Check if plan selection params are present and valid
    #
    # Validates that both product and interval are present without
    # performing full catalog lookup. Useful for quick validation
    # before storing in session.
    #
    # @param product [String, nil] Product identifier
    # @param interval [String, nil] Billing interval
    # @return [Boolean] True if params appear valid
    #
    def valid_params?(product:, interval:)
      return false if product.nil? || product.to_s.strip.empty?
      return false if interval.nil? || interval.to_s.strip.empty?

      normalized = normalize_interval(interval)
      !normalized.nil?
    end

    private

    # Normalize interval to standard format
    #
    # Accepts various interval formats and normalizes to 'monthly' or 'yearly'.
    #
    # @param interval [String] Input interval
    # @return [String, nil] Normalized interval or nil if invalid
    #
    def normalize_interval(interval)
      case interval.to_s.downcase.strip
      when 'monthly', 'month'
        'monthly'
      when 'yearly', 'year', 'annual', 'annually'
        'yearly'
      end
    end

    # Create error result
    #
    # @param message [String] Error message
    # @return [Result] Failed result with error
    #
    def error_result(message)
      Result.new(
        success: false,
        plan_id: nil,
        tier: nil,
        billing_cycle: nil,
        plan: nil,
        error: message,
      )
    end
  end
end
