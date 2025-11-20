# lib/onetime/billing/catalog_definitions.rb
#
# frozen_string_literal: true
#
# Billing Catalog Utility Methods
#
# NOTE: Catalog definitions are now stored in Stripe and cached via CatalogCache.
# See docs/billing/catalog-definitions.md for reference documentation.
#
# These utility methods provide helpers for catalog names and upgrade paths
# based on plan_id naming conventions.

module Onetime
  module Billing
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
    # Finds the most affordable catalog item that includes the requested capability
    # by querying the cached catalog.
    #
    # @param capability [String] Required capability
    # @param current_plan [String, nil] Current plan ID (unused, for compatibility)
    # @return [String, nil] Suggested plan ID or nil
    #
    # @example
    #   Billing.upgrade_path_for('custom_domains', 'free')
    #   # => "identity_v1_monthly"
    def self.upgrade_path_for(capability, _current_plan = nil)
      # Query cached catalog for items with the capability
      catalog_with_capability = ::Billing::Models::CatalogCache.list_catalog.select do |item|
        item.parsed_capabilities.include?(capability.to_s)
      end

      return nil if catalog_with_capability.empty?

      # Sort by tier preference: free < single_team < multi_team
      # Return first (cheapest) matching item
      tier_order = %w[free single_team multi_team]
      sorted_catalog = catalog_with_capability.sort_by do |item|
        tier_order.index(item.tier) || 999
      end

      sorted_catalog.first&.plan_id
    end

    # Get human-readable plan name
    #
    # Converts plan_id to display name based on naming conventions.
    # Falls back to CatalogCache name if available.
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
      plan = ::Billing::Models::CatalogCache.load(plan_id)
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
    # Returns list of current catalog items, excluding legacy v0 plans.
    #
    # @return [Array<String>] List of current plan IDs
    def self.available_plans
      ::Billing::Models::CatalogCache.list_catalog
        .reject { |item| legacy_plan?(item.plan_id) }
        .map(&:plan_id)
    end
  end
end
