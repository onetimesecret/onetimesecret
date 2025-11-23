# apps/web/billing/plan_definitions.rb
#
# frozen_string_literal: true

#
# Billing Plan Utility Methods
#
# NOTE: Plan definitions are now stored in Stripe and cached via Plan model.
# See docs/billing/plan-definitions.md for reference documentation.
#
# These utility methods provide helpers for plan names and upgrade paths
# based on plan_id naming conventions.

module Billing
  module PlanDefinitions
    # Capability categories for documentation and UI grouping
    CAPABILITY_CATEGORIES = {
      core: %w[
        create_secrets
        basic_sharing
        view_metadata
      ],
      collaboration: %w[
        create_team
        create_teams
      ],
      infrastructure: %w[
        custom_domains
        api_access
      ],
      support: [
        'priority_support',
      ],
      advanced: %w[
        audit_logs
        advanced_analytics
        extended_lifetime
      ],
    }.freeze

    # Get upgrade path when capability is missing
    #
    # Finds the most affordable plan that includes the requested capability
    # by querying the cached plans.
    #
    # @param capability [String] Required capability
    # @param current_plan [String, nil] Current plan ID (unused, for compatibility)
    # @return [String, nil] Suggested plan ID or nil
    #
    # @example
    #   Billing::PlanDefinitions.upgrade_path_for('custom_domains', 'free')
    #   # => "identity_plus_v1_monthly"
    def self.upgrade_path_for(capability, _current_plan = nil)
      # Query cached plans for items with the capability
      plans_with_capability = ::Billing::Plan.list_plans.select do |item|
        item.capabilities.member?(capability.to_s)
      end

      return nil if plans_with_capability.empty?

      # Sort by tier preference: free < identity_plus < team_plus < org_plus < org_max
      # Return first (cheapest) matching item
      tier_order   = %w[free identity_plus team_plus org_plus org_max]
      sorted_plans = plans_with_capability.sort_by do |item|
        tier_order.index(item.tier) || 999
      end

      sorted_plans.first&.plan_id
    end

    # Get human-readable plan name
    #
    # Converts plan_id to display name based on naming conventions.
    # Falls back to Plan model name if available.
    #
    # @param plan_id [String] Plan identifier
    # @return [String] Formatted plan name
    #
    # @example
    #   Billing::PlanDefinitions.plan_name('identity_plus_v1_monthly')  # => "Identity Plus"
    #   Billing::PlanDefinitions.plan_name('team_plus_v1')        # => "Team Plus"
    def self.plan_name(plan_id)
      return plan_id if plan_id.to_s.empty?

      # Try to get name from cached plan first
      item = ::Billing::Plan.load(plan_id)
      return item.name if item&.name

      # Fall back to pattern matching on plan_id
      case plan_id
      when 'free'
        'Free'
      when /identity_v(\d+)/
        version = Regexp.last_match(1)
        version == '1' ? 'Identity Plus' : "Identity Plus (v#{version})"
      when /multi_team_v(\d+)/
        version = Regexp.last_match(1)
        version == '1' ? 'Multi-Team' : "Multi-Team (v#{version})"
      else
        # Try to make a readable name from plan_id
        plan_id.split('_').map(&:capitalize).join(' ')
      end
    end

    class << self
      alias catalog_name plan_name
    end

    # Check if plan is legacy
    #
    # Determines if a plan is legacy/grandfathered based on version number.
    # v0 items are considered legacy, v1+ are current.
    #
    # @param plan_id [String] Plan identifier
    # @return [Boolean] True if plan is legacy (v0)
    def self.legacy_plan?(plan_id)
      return false if plan_id.to_s.empty?

      # v0 plans are legacy, v1+ are current
      plan_id.match?(/_v0(_|$)/)
    end

    # Get all available (non-legacy) plan IDs
    #
    # Returns list of current plans, excluding legacy v0 items.
    #
    # @return [Array<String>] List of current plan IDs
    def self.available_plans
      ::Billing::Plan.list_plans
        .reject { |item| legacy_plan?(item.plan_id) }
        .map(&:plan_id)
    end

    class << self
      alias available_catalogs available_plans
    end
  end
end
