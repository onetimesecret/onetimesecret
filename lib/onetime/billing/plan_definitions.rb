# lib/onetime/billing/plan_definitions.rb

module Onetime
  module Billing
    # Plan Definitions - Single Source of Truth for Plan Capabilities
    #
    # Each plan defines:
    # - version: Plan version (for tracking legacy vs current)
    # - legacy: Boolean flag for grandfathered plans
    # - capabilities: Array of feature strings
    # - limits: Hash of resource limits (Float::INFINITY for unlimited)
    #
    # Plan IDs use format: tier_v{version}
    # Examples: free, identity_v1, multi_team_v1, identity_v0 (legacy)
    #
    # New capabilities should be:
    # - Added to relevant plans
    # - Documented here
    # - Checked with org.can?('capability_name')
    #
    PLAN_DEFINITIONS = {
      # Free tier - Default for all organizations without subscription
      'free' => {
        version: 1,
        capabilities: [
          'create_secrets',      # Can create basic secrets
          'basic_sharing',       # Can share via link/email
          'view_metadata',       # Can view secret metadata
        ],
        limits: {
          secrets_per_day: 10,
          secret_lifetime: 7 * 24 * 60 * 60, # 7 days in seconds
        }
      },

      # Identity Plus (current) - Single team plan
      'identity_v1' => {
        version: 1,
        capabilities: [
          'create_secrets',
          'basic_sharing',
          'view_metadata',
          'create_team',         # Can create ONE team
          'custom_domains',      # Can configure custom domains
          'priority_support',    # Priority customer support
          'extended_lifetime',   # Longer secret retention
        ],
        limits: {
          teams: 1,
          members_per_team: Float::INFINITY,
          custom_domains: Float::INFINITY,
          secret_lifetime: 30 * 24 * 60 * 60, # 30 days in seconds
        }
      },

      # Multi-Team (current) - Unlimited teams plan
      'multi_team_v1' => {
        version: 1,
        capabilities: [
          'create_secrets',
          'basic_sharing',
          'view_metadata',
          'create_teams',        # Can create MULTIPLE teams (note plural)
          'custom_domains',
          'api_access',          # API access enabled
          'priority_support',
          'extended_lifetime',
          'audit_logs',          # Access to audit log features
          'advanced_analytics',  # Advanced usage analytics
        ],
        limits: {
          teams: Float::INFINITY,
          members_per_team: Float::INFINITY,
          custom_domains: Float::INFINITY,
          api_rate_limit: 10_000,  # requests per hour
          secret_lifetime: 90 * 24 * 60 * 60, # 90 days in seconds
        }
      },

      # Legacy Identity (v0) - Grandfathered plan
      # Lower limits than v1, no custom domains
      'identity_v0' => {
        version: 0,
        legacy: true,
        capabilities: [
          'create_secrets',
          'basic_sharing',
          'view_metadata',
          'create_team',
          'priority_support',
          # Note: NO custom_domains for v0
        ],
        limits: {
          teams: 1,
          members_per_team: 10,  # Old limit was 10 members
          secret_lifetime: 14 * 24 * 60 * 60, # 14 days in seconds
        }
      },

      # Legacy Multi-Team (v0) - Grandfathered plan
      'multi_team_v0' => {
        version: 0,
        legacy: true,
        capabilities: [
          'create_secrets',
          'basic_sharing',
          'view_metadata',
          'create_teams',
          'api_access',
          'priority_support',
          # Note: NO custom_domains or audit_logs for v0
        ],
        limits: {
          teams: Float::INFINITY,
          members_per_team: 25,  # Old limit
          api_rate_limit: 5_000, # Lower rate limit
          secret_lifetime: 30 * 24 * 60 * 60, # 30 days in seconds
        }
      }
    }.freeze

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
    # Finds the most affordable non-legacy plan that includes the requested capability.
    # Returns nil if no plan offers the capability.
    #
    # @param capability [String] Required capability
    # @param current_plan [String, nil] Current plan ID (for logging/analytics)
    # @return [String, nil] Suggested plan ID or nil
    #
    # @example
    #   Billing.upgrade_path_for('custom_domains', 'free')
    #   # => "identity_v1"
    #
    #   Billing.upgrade_path_for('audit_logs', 'identity_v1')
    #   # => "multi_team_v1"
    def self.upgrade_path_for(capability, current_plan = nil)
      # Find all non-legacy plans with this capability
      plans_with_capability = PLAN_DEFINITIONS.select do |plan_id, plan_def|
        !plan_def[:legacy] && plan_def[:capabilities]&.include?(capability.to_s)
      end

      return nil if plans_with_capability.empty?

      # Sort by assumed pricing order: free < identity < multi_team
      # Return first (cheapest) matching plan
      plan_order = ['free', 'identity_v1', 'multi_team_v1']
      plan_order.find { |plan_id| plans_with_capability.key?(plan_id) } ||
        plans_with_capability.keys.first
    end

    # Get human-readable plan name
    #
    # @param plan_id [String] Plan identifier
    # @return [String] Formatted plan name
    #
    # @example
    #   Billing.plan_name('identity_v1')  # => "Identity Plus"
    #   Billing.plan_name('multi_team_v1') # => "Multi-Team"
    def self.plan_name(plan_id)
      case plan_id
      when 'free'
        'Free'
      when /^identity_v(\d+)/
        version = Regexp.last_match(1)
        version == '1' ? 'Identity Plus' : "Identity Plus (v#{version})"
      when /^multi_team_v(\d+)/
        version = Regexp.last_match(1)
        version == '1' ? 'Multi-Team' : "Multi-Team (v#{version})"
      else
        plan_id
      end
    end

    # Check if plan is legacy
    #
    # @param plan_id [String] Plan identifier
    # @return [Boolean] True if plan is marked legacy
    def self.legacy_plan?(plan_id)
      plan_def = PLAN_DEFINITIONS[plan_id]
      plan_def&.[](:legacy) == true
    end

    # Get all available (non-legacy) plan IDs
    #
    # @return [Array<String>] List of current plan IDs
    def self.available_plans
      PLAN_DEFINITIONS.reject { |_id, plan_def| plan_def[:legacy] }.keys
    end

  end
end
