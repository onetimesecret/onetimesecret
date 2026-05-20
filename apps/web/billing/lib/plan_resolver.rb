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
  # ## Terminology: interval vs billing_cycle
  #
  # Following Stripe's conventions:
  #   - `interval` = Stripe price frequency strings ('month', 'year')
  #   - `billing_cycle` = adverb form for UI/API ('monthly', 'yearly')
  #
  # The frontend sends `interval` in various forms (month, monthly, year,
  # yearly, annual, annually). We normalize to Stripe strings internally,
  # then convert to adverb form for Result.billing_cycle.
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
  #     # result.plan_id => 'identity_plus_v1' (canonical family ID)
  #     # result.tier => 'identity'
  #     # result.billing_cycle => 'monthly'
  #     # result.checkout_url => '/billing/api/org/:extid/checkout'
  #   else
  #     # result.error => 'Plan not found'
  #   end
  #
  module PlanResolver
    extend self

    # Canonical plan ID format: lowercase alphanumeric with underscores, ending in version
    # Examples: identity_plus_v1, team_v2, starter_v1
    # Rejects: identity_plus_v1_monthly (interval suffix), Identity_Plus_V1 (uppercase)
    CANONICAL_PLAN_ID_PATTERN = /\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*_v\d+\z/

    # Result struct for plan resolution
    #
    # @attr success [Boolean] Whether resolution succeeded
    # @attr plan_id [String, nil] Canonical family ID (e.g., 'identity_plus_v1')
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
    # Interval normalization: Accepts 'month', 'monthly', 'year', 'yearly',
    # 'annual', 'annually'. Internally normalizes to Stripe strings ('month',
    # 'year') for price lookups, then converts to adverb form ('monthly',
    # 'yearly') for Result.billing_cycle. This catches easy human errors
    # mixing up "month" with "monthly" while keeping the UI-friendly form.
    #
    # @param product [String] Product identifier (e.g., 'identity_plus_v1')
    # @param interval [String] Billing interval (accepts month/monthly/year/yearly/annual/annually)
    # @return [Result] Resolution result with plan details or error
    #
    def resolve(product:, interval:)
      # Validate inputs
      return error_result('Missing product') if product.nil? || product.to_s.strip.empty?
      return error_result('Missing interval') if interval.nil? || interval.to_s.strip.empty?

      # Normalize interval
      normalized_interval = normalize_interval(interval)
      unless normalized_interval
        return error_result("Invalid interval: #{interval}. Accepts: month, monthly, year, yearly, annual, annually")
      end

      # Validate canonical plan ID format (rejects interval-suffixed IDs)
      unless canonical_plan_id?(product)
        return error_result("Invalid plan ID format: #{product}. Expected format like 'identity_plus_v1'")
      end

      # Plan IDs are family-keyed (unsuffixed). The product param IS the plan_id.
      # Interval variants live inside the plan's prices hash, keyed by 'month'/'year'.
      plan_id      = product.to_s
      interval_str = normalized_interval  # Already 'month' or 'year' from normalize_interval

      # For external API: convert to adverb form
      billing_cycle = { 'month' => 'monthly', 'year' => 'yearly' }.fetch(interval_str)

      # Look up plan in catalog
      plan = Billing::Plan.load(plan_id)
      if plan&.exists?
        # Verify the plan has a price for the requested interval
        unless plan.available_intervals.include?(interval_str)
          return error_result(
            "Plan #{plan_id} has no #{interval_str} price (available: #{plan.available_intervals.join(', ')})",
          )
        end

        return Result.new(
          success: true,
          plan_id: plan.plan_id,
          tier: plan.tier,
          billing_cycle: billing_cycle,
          plan: plan,
          error: nil,
        )
      end

      # Try config fallback for dev/test environments
      config_plan = Billing::Plan.load_from_config(plan_id)
      if config_plan
        return Result.new(
          success: true,
          plan_id: plan_id,
          tier: config_plan[:tier],
          billing_cycle: billing_cycle,
          plan: nil,
          error: nil,
        )
      end

      error_result("Plan not found: #{plan_id}")
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
      return false unless canonical_plan_id?(product)

      normalized = normalize_interval(interval)
      !normalized.nil?
    end

    # Check if product matches canonical plan ID format
    #
    # @param product [String] Product identifier to validate
    # @return [Boolean] True if format is valid
    #
    def canonical_plan_id?(product)
      CANONICAL_PLAN_ID_PATTERN.match?(product.to_s)
    end

    private

    # Normalize interval to Stripe's convention
    #
    # Accepts various interval formats (adverb forms common in UI text)
    # and normalizes to Stripe's 'month'/'year' strings.
    #
    # @param interval [String] Input interval
    # @return [String, nil] 'month', 'year', or nil if invalid
    #
    def normalize_interval(interval)
      case interval.to_s.downcase.strip
      when 'monthly', 'month'
        'month'
      when 'yearly', 'year', 'annual', 'annually'
        'year'
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
