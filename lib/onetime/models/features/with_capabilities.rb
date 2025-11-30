# lib/onetime/models/features/with_capabilities.rb
#
# frozen_string_literal: true

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

        # Full capability set for standalone mode
        # When billing is disabled or plan cache is empty, users get full access
        STANDALONE_CAPABILITIES = %w[
          create_secrets basic_sharing create_team create_teams
          custom_domains api_access priority_support audit_logs
        ].freeze

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
          # Falls back to full standalone capabilities if:
          # - billing is disabled (standalone mode)
          # - plan not found in cache
          #
          # This ensures full feature access in standalone mode.
          #
          # @example
          #   org.capabilities  # => ["create_secrets", "create_team", "custom_domains"]
          def capabilities
            # Standalone fallback: full access when billing disabled
            unless billing_enabled?
              return WithCapabilities::STANDALONE_CAPABILITIES.dup
            end

            return [] if planid.to_s.empty?

            plan = ::Billing::Plan.load(planid)

            # When billing enabled but no plan (SaaS free tier), fail-closed
            return [] unless plan

            plan.capabilities.to_a
          end

          # Get limit for a specific resource
          #
          # @param resource [String, Symbol] Resource to check limit for
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          #
          # Falls back to unlimited for self-hosted installations.
          #
          # @example
          #   org.limit_for('teams')            # => 1
          #   org.limit_for(:members_per_team)  # => Float::INFINITY
          #   org.limit_for('unknown')          # => 0
          def limit_for(resource)
            # Standalone fallback: unlimited when billing disabled
            return Float::INFINITY unless billing_enabled?

            return 0 if planid.to_s.empty?

            plan = ::Billing::Plan.load(planid)

            # When billing enabled but no plan (SaaS free tier), fail-closed
            return 0 unless plan

            # Flattened key: "teams" => "teams.max"
            key = resource.to_s.include?('.') ? resource.to_s : "#{resource}.max"
            val = plan.limits[key]

            # Convert "unlimited" to Float::INFINITY, strings to integers
            return 0 if val.nil? || val.empty?
            return Float::INFINITY if val == 'unlimited'

            val.to_i
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
            result  = {
              allowed: allowed,
              capability: capability.to_s,
              current_plan: planid,
              upgrade_needed: !allowed,
            }

            unless allowed
              result[:upgrade_to] = Billing::PlanHelpers.upgrade_path_for(capability, planid)
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

          private

          # Check if billing system is enabled
          # Returns false in standalone mode
          def billing_enabled?
            Onetime::BillingConfig.instance.enabled?
          rescue StandardError
            false # If BillingConfig fails, assume billing disabled
          end
        end
      end
    end
  end
end
