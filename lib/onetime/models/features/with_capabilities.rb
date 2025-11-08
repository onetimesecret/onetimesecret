# lib/onetime/models/features/with_capabilities.rb

module Onetime
  module Models
    module Features
      # Capability-Based Authorization Feature
      #
      # Adds capability checking to models (primarily Organization).
      # Features and limits are separated:
      # - Capabilities: Can the org do X? (boolean check)
      # - Limits: How many times can org do X? (numeric/quota check)
      #
      # Usage:
      #   org.can?('create_team')           # => true/false
      #   org.capabilities                  # => ["create_secrets", "create_team", ...]
      #   org.limit_for('teams')            # => 1 (or Float::INFINITY)
      #   org.check_capability('api_access') # => {allowed: false, upgrade_needed: true, ...}
      #
      module WithCapabilities

        Familia::Base.add_feature self, :with_capabilities

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.include InstanceMethods
        end

        module InstanceMethods

          # Check if organization has a specific capability
          #
          # @param capability [String, Symbol] Capability to check
          # @return [Boolean] True if org has the capability
          #
          # @example
          #   org.can?('custom_domains')  # => true
          #   org.can?(:api_access)       # => false
          def can?(capability)
            capabilities.include?(capability.to_s)
          end

          # Get all capabilities for current plan
          #
          # @return [Array<String>] List of capability strings
          #
          # Falls back safely to empty array if:
          # - planid is nil/empty
          # - plan definition not found
          # - capabilities key missing from plan
          #
          # @example
          #   org.capabilities  # => ["create_secrets", "create_team", "custom_domains"]
          def capabilities
            return [] if planid.to_s.empty?

            plan_def = Onetime::Billing::PLAN_DEFINITIONS[planid]
            return [] unless plan_def  # Fail safely

            plan_def[:capabilities] || []
          end

          # Get limit for a specific resource
          #
          # @param resource [String, Symbol] Resource to check limit for
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          #
          # Falls back safely to 0 (no access) if:
          # - planid is nil/empty
          # - plan definition not found
          # - limits hash missing
          # - resource not in limits (fail-closed for security)
          #
          # @example
          #   org.limit_for('teams')            # => 1
          #   org.limit_for(:members_per_team)  # => Float::INFINITY
          #   org.limit_for('unknown')          # => 0
          def limit_for(resource)
            return 0 if planid.to_s.empty?

            plan_def = Onetime::Billing::PLAN_DEFINITIONS[planid]
            return 0 unless plan_def

            limits = plan_def[:limits] || {}
            # Default to 0 for unknown resources (fail-closed for security)
            # This prevents typos from granting unlimited access
            limits.fetch(resource.to_sym, 0)
          end

          # Check capability with detailed response for upgrade messaging
          #
          # @param capability [String, Symbol] Capability to check
          # @return [Hash] Result with upgrade path information
          #
          # Response includes:
          # - allowed: boolean indicating if capability is available
          # - capability: the requested capability
          # - current_plan: organization's current plan ID
          # - upgrade_needed: boolean indicating if upgrade required
          # - upgrade_to: suggested plan ID (if upgrade needed)
          #
          # @example
          #   org.check_capability('custom_domains')
          #   # => {
          #   #   allowed: false,
          #   #   capability: "custom_domains",
          #   #   current_plan: "free",
          #   #   upgrade_needed: true,
          #   #   upgrade_to: "identity_v1"
          #   # }
          def check_capability(capability)
            allowed = can?(capability)
            result = {
              allowed: allowed,
              capability: capability.to_s,
              current_plan: planid,
              upgrade_needed: !allowed
            }

            if !allowed
              result[:upgrade_to] = Onetime::Billing.upgrade_path_for(capability, planid)
            end

            result
          end

          # Check if organization is at or over limit for a resource
          #
          # @param resource [String, Symbol] Resource to check
          # @param current_count [Integer] Current usage count
          # @return [Boolean] True if at or over limit
          #
          # @example
          #   org.at_limit?('teams', 1)  # => true (if limit is 1)
          #   org.at_limit?('teams', 0)  # => false
          def at_limit?(resource, current_count)
            limit = limit_for(resource)
            return false if limit == Float::INFINITY

            current_count >= limit
          end

        end

      end

    end
  end
end
