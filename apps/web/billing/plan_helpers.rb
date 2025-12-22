# apps/web/billing/plan_helpers.rb
#
# frozen_string_literal: true

#
# Billing Plan Runtime Helpers
#
# Utility methods for querying cached plans from Stripe.
# Plan definitions live in etc/billing.yaml and are
# synced to Redis cache via Billing::Plan model.
#
# See docs/billing/plan-definitions.md for catalog reference.
#

module Billing
  module PlanHelpers
    # Get upgrade path when entitlement is missing
    #
    # Finds the most affordable plan that includes the requested entitlement
    # by querying the cached plans and sorting by tier.
    #
    # @param entitlement [String] Required entitlement
    # @param _current_plan [String, nil] Current plan ID (unused, for compatibility)
    # @return [String, nil] Suggested plan ID or nil
    #
    # @example
    #   Billing::PlanHelpers.upgrade_path_for('custom_domains')
    #   # => "identity_plus_v1"
    def self.upgrade_path_for(entitlement, _current_plan = nil)
      # Query cached plans for those with the entitlement
      plans_with_entitlement = ::Billing::Plan.list_plans.select do |plan|
        plan.show_on_plans_page && plan.entitlements.member?(entitlement.to_s)
      end

      return nil if plans_with_entitlement.empty?

      # Sort by tier order (free < single_team < multi_team)
      # Then by display_order (higher first for same tier)
      # Return first (cheapest/simplest) matching plan
      sorted_plans = plans_with_entitlement.sort_by do |plan|
        [tier_priority(plan.tier), -(plan.display_order.to_i)]
      end

      sorted_plans.first&.plan_id
    end

    # Get human-readable plan name
    #
    # Retrieves plan name from cached Plan model.
    # Falls back to plan_id if not found in cache.
    #
    # @param plan_id [String] Plan identifier
    # @return [String] Formatted plan name
    #
    # @example
    #   Billing::PlanHelpers.plan_name('identity_plus_v1')  # => "Identity Plus"
    #   Billing::PlanHelpers.plan_name('unknown_plan')      # => "unknown_plan"
    def self.plan_name(plan_id)
      return plan_id if plan_id.to_s.empty?

      # Get name from cached plan
      plan = ::Billing::Plan.load(plan_id)
      return plan.name if plan&.name

      # Fallback to plan_id if not in cache
      plan_id
    end

    # Check if plan is legacy
    #
    # Determines if a plan is legacy/grandfathered based on version number.
    # v0 plans are considered legacy, v1+ are current.
    #
    # @param plan_id [String] Plan identifier
    # @return [Boolean] True if plan is legacy (v0)
    #
    # @example
    #   Billing::PlanHelpers.legacy_plan?('identity_v0')  # => true
    #   Billing::PlanHelpers.legacy_plan?('identity_plus_v1')  # => false
    def self.legacy_plan?(plan_id)
      return false if plan_id.to_s.empty?

      # v0 plans are legacy, v1+ are current
      plan_id.match?(/_v0(_|$)/)
    end

    # Get all available (non-legacy) plan IDs
    #
    # Returns list of current plans from cache, excluding legacy v0 plans.
    #
    # @return [Array<String>] List of current plan IDs
    #
    # @example
    #   Billing::PlanHelpers.available_plans
    #   # => ["free_v1", "identity_plus_v1", "team_plus_v1", ...]
    def self.available_plans
      ::Billing::Plan.list_plans
        .reject { |plan| legacy_plan?(plan.plan_id) }
        .map(&:plan_id)
    end

    # Get cheapest plan with entitlement
    #
    # Alias for upgrade_path_for with clearer intent.
    #
    # @param entitlement [String] Required entitlement
    # @return [String, nil] Cheapest plan ID with entitlement
    def self.cheapest_plan_with(entitlement)
      upgrade_path_for(entitlement)
    end

    # Get tier priority for sorting (lower = higher priority/cheaper)
    #
    # @param tier [String] Tier name
    # @return [Integer] Sort priority
    def self.tier_priority(tier)
      case tier.to_s
      when 'free' then 0
      when 'single_team' then 1
      when 'multi_team' then 2
      else 999 # Unknown tiers sort last
      end
    end
  end
end
