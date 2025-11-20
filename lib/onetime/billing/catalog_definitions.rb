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
# based on catalog_id naming conventions.

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
    # @param current_plan [String, nil] Current catalog ID (unused, for compatibility)
    # @return [String, nil] Suggested catalog ID or nil
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

      sorted_catalog.first&.catalog_id
    end

    # Get human-readable catalog name
    #
    # Converts catalog_id to display name based on naming conventions.
    # Falls back to CatalogCache name if available.
    #
    # @param catalog_id [String] Catalog identifier
    # @return [String] Formatted catalog name
    #
    # @example
    #   Billing.catalog_name('identity_v1_monthly')  # => "Identity Plus"
    #   Billing.catalog_name('multi_team_v1')        # => "Multi-Team"
    def self.catalog_name(catalog_id)
      return catalog_id if catalog_id.to_s.empty?

      # Try to get name from cached catalog first
      item = ::Billing::Models::CatalogCache.load(catalog_id)
      return item.name if item&.name

      # Fall back to pattern matching on catalog_id
      case catalog_id
      when 'free'
        'Free'
      when /identity_v(\d+)/
        version = Regexp.last_match(1)
        version == '1' ? 'Identity Plus' : "Identity Plus (v#{version})"
      when /multi_team_v(\d+)/
        version = Regexp.last_match(1)
        version == '1' ? 'Multi-Team' : "Multi-Team (v#{version})"
      else
        # Try to make a readable name from catalog_id
        catalog_id.split('_').map(&:capitalize).join(' ')
      end
    end

    # Check if catalog item is legacy
    #
    # Determines if a catalog item is legacy/grandfathered based on version number.
    # v0 items are considered legacy, v1+ are current.
    #
    # @param catalog_id [String] Catalog identifier
    # @return [Boolean] True if catalog item is legacy (v0)
    def self.legacy_plan?(catalog_id)
      return false if catalog_id.to_s.empty?

      # v0 plans are legacy, v1+ are current
      catalog_id.match?(/_v0(_|$)/)
    end

    # Get all available (non-legacy) catalog IDs
    #
    # Returns list of current catalog items, excluding legacy v0 items.
    #
    # @return [Array<String>] List of current catalog IDs
    def self.available_catalogs
      ::Billing::Models::CatalogCache.list_catalog
        .reject { |item| legacy_plan?(item.catalog_id) }
        .map(&:catalog_id)
    end
  end
end
