# lib/onetime/billing/plan_definitions.rb
#
# Plan Utility Methods
#
# NOTE: Plan definitions are now stored in Stripe and cached via PlanCache.
# See docs/billing/plan-definitions.md for reference documentation.
#
# These utility methods provide helpers for plan names and upgrade paths
# based on plan_id naming conventions.

module Onetime
  module Billing

    # Capability categories for documentation and UI grouping
    CAPABILITY_CATEGORIES = {
      core: [
        'create_secrets',
        'basic_sharing',
        'view_metadata',
      ],
      collaboration: [
        'create_team',
        'create_teams',
      ],
      infrastructure: [
        'custom_domains',
        'api_access',
      ],
      support: [
        'priority_support',
      ],
      advanced: [
        'audit_logs',
        'advanced_analytics',
        'extended_lifetime',
      ]
    }.freeze

    # Get upgrade path when capability is missing
    #
    # Finds the most affordable plan that includes the requested capability
    # by querying cached plans.
    #
    # @param capability [String] Required capability
    # @param current_plan [String, nil] Current plan ID (unused, for compatibility)
    # @return [String, nil] Suggested plan ID or nil
    #
    # @example
    #   Billing.upgrade_path_for('custom_domains', 'free')
    #   # => "identity_v1_monthly"
    def self.upgrade_path_for(capability, current_plan = nil)
      # Query all cached plans for those with the capability
      plans_with_capability = ::Billing::Models::PlanCache.list_plans.select do |plan|
        plan.parsed_capabilities.include?(capability.to_s)
      end

      return nil if plans_with_capability.empty?

      # Sort by tier preference: free < single_team < multi_team
      # Return first (cheapest) matching plan
      tier_order = ['free', 'single_team', 'multi_team']
      sorted_plans = plans_with_capability.sort_by do |plan|
        tier_order.index(plan.tier) || 999
      end

      sorted_plans.first&.plan_id
    end

    # Get human-readable plan name
    #
    # Converts plan_id to display name based on naming conventions.
    # Falls back to PlanCache name if available.
    #
    # @param plan_id [String] Plan identifier
    # @return [String] Formatted plan name
    #
    # @example
    #   Billing.plan_name('identity_v1_monthly')  # => "Identity Plus"
    #   Billing.plan_name('multi_team_v1')        # => "Multi-Team"
    def self.plan_name(plan_id)
      return plan_id if plan_id.to_s.empty?

      # Try to get name from cached plan first
      plan = ::Billing::Models::PlanCache.load(plan_id)
      return plan.name if plan&.name

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

    # Check if plan is legacy
    #
    # Determines if a plan is a legacy/grandfathered plan based on version number.
    # v0 plans are considered legacy, v1+ are current.
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
    # Returns list of current plans from cache, excluding legacy v0 plans.
    #
    # @return [Array<String>] List of current plan IDs
    def self.available_plans
      ::Billing::Models::PlanCache.list_plans
        .reject { |plan| legacy_plan?(plan.plan_id) }
        .map(&:plan_id)
    end

  end
end
