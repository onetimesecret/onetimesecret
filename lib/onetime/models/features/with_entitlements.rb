# lib/onetime/models/features/with_entitlements.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Entitlement-Based Authorization Feature
      #
      # Adds entitlement checking to models (primarily Organization).
      # Features and limits are separated:
      # - Entitlements: Can the org do X? (boolean check)
      # - Limits: How many times can org do X? (numeric/quota check)
      #
      # Usage:
      #   org.can?('create_team')           # => true/false
      #   org.entitlements                  # => ["create_secrets", "create_team", ...]
      #   org.limit_for('teams')            # => 1 (or Float::INFINITY)
      #   org.check_entitlement('api_access') # => {allowed: false, upgrade_needed: true, ...}
      #
      module WithEntitlements
        Familia::Base.add_feature self, :with_entitlements

        # Full entitlement set for standalone mode
        # When billing is disabled or plan cache is empty, users get full access
        STANDALONE_ENTITLEMENTS = %w[
          create_secrets basic_sharing create_team create_teams
          custom_domains api_access priority_support audit_logs
        ].freeze

        # Minimal fallback plans for dev environments when Billing::Plan cache is empty
        # Used only when billing is enabled but plan lookup fails (last resort)
        FALLBACK_PLANS = {
          'free' => {
            entitlements: %w[create_secrets basic_sharing],
            limits: { 'secrets.max' => '10', 'recipients.max' => '1' },
          },
          'identity_plus_v1_monthly' => {
            entitlements: %w[create_secrets custom_domains create_organization priority_support],
            limits: { 'secrets.max' => '100', 'recipients.max' => '10', 'organizations.max' => '1' },
          },
          'multi_team_v1_monthly' => {
            entitlements: %w[create_secrets custom_domains create_organization api_access audit_logs advanced_analytics],
            limits: { 'secrets.max' => 'unlimited', 'recipients.max' => 'unlimited', 'organizations.max' => '5' },
          },
        }.freeze

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.include InstanceMethods
        end

        module InstanceMethods
          # Check if organization has a specific entitlement
          #
          # @param entitlement [String, Symbol] Entitlement to check
          # @return [Boolean] True if org has the entitlement
          #
          # @example
          #   org.can?('custom_domains')  # => true
          #   org.can?(:api_access)       # => false
          def can?(entitlement)
            entitlements.include?(entitlement.to_s)
          end

          # Get all entitlements for current plan
          #
          # @return [Array<String>] List of entitlement strings
          #
          # Falls back to full standalone entitlements if:
          # - billing is disabled (standalone mode)
          # - plan not found in cache
          #
          # This ensures full feature access in standalone mode.
          #
          # @example
          #   org.entitlements  # => ["create_secrets", "create_team", "custom_domains"]
          def entitlements
            # Colonel test mode override - check Thread.current set by middleware
            # Empty string should fall back to actual plan (same as nil)
            test_planid = Thread.current[:entitlement_test_planid]
            if test_planid && !test_planid.empty?
              return test_plan_entitlements(test_planid)
            end

            # Standalone fallback: full access when billing disabled
            unless billing_enabled?
              return WithEntitlements::STANDALONE_ENTITLEMENTS.dup
            end

            return [] if planid.to_s.empty?

            plan = ::Billing::Plan.load(planid)

            # When billing enabled but no plan (SaaS free tier), fail-closed
            return [] unless plan

            plan.entitlements.to_a
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
            # Colonel test mode override - check Thread.current set by middleware
            # Empty string should fall back to actual plan (same as nil)
            test_planid = Thread.current[:entitlement_test_planid]
            if test_planid && !test_planid.empty?
              return test_plan_limit_for(test_planid, resource)
            end

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

          # Check entitlement with detailed response for upgrade messaging
          #
          # @param entitlement [String, Symbol] Entitlement to check
          # @return [Hash] Result with upgrade path information
          #
          # Response includes:
          # - allowed: boolean indicating if entitlement is available
          # - entitlement: the requested entitlement
          # - current_plan: organization's current plan ID
          # - upgrade_needed: boolean indicating if upgrade required
          # - upgrade_to: suggested plan ID (if upgrade needed)
          #
          # @example
          #   org.check_entitlement('custom_domains')
          #   # => {
          #   #   allowed: false,
          #   #   entitlement: "custom_domains",
          #   #   current_plan: "free",
          #   #   upgrade_needed: true,
          #   #   upgrade_to: "identity_v1"
          #   # }
          def check_entitlement(entitlement)
            allowed = can?(entitlement)
            result  = {
              allowed: allowed,
              entitlement: entitlement.to_s,
              current_plan: planid,
              upgrade_needed: !allowed,
            }

            unless allowed
              result[:upgrade_to] = Billing::PlanHelpers.upgrade_path_for(entitlement, planid)
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

          # Get entitlements for a test plan (colonel test mode)
          #
          # Checks Billing::Plan cache first (production/Stripe-synced), then falls back
          # to minimal FALLBACK_PLANS (for development when billing cache is empty).
          #
          # @param test_planid [String] Plan ID to test
          # @return [Array<String>] List of entitlements for the test plan
          def test_plan_entitlements(test_planid)
            # Check Billing::Plan cache first (production/testing)
            plan = ::Billing::Plan.load(test_planid)
            return plan.entitlements.to_a if plan

            # Fall back to minimal dev plans when cache is empty
            if (fallback_config = WithEntitlements::FALLBACK_PLANS[test_planid])
              return fallback_config[:entitlements].dup
            end

            []
          end

          # Get limit for a resource from a test plan (colonel test mode)
          #
          # Checks Billing::Plan cache first (production/Stripe-synced), then falls back
          # to minimal FALLBACK_PLANS (for development when billing cache is empty).
          #
          # @param test_planid [String] Plan ID to test
          # @param resource [String, Symbol] Resource to check limit for
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          def test_plan_limit_for(test_planid, resource)
            # Flattened key: "teams" => "teams.max"
            key = resource.to_s.include?('.') ? resource.to_s : "#{resource}.max"

            # Check Billing::Plan cache first (production/testing)
            plan = ::Billing::Plan.load(test_planid)
            if plan
              limits_hash = plan.limits.hgetall || {}
              val         = limits_hash[key]
              return 0 if val.nil? || val.to_s.empty?
              return Float::INFINITY if val == 'unlimited'

              return val.to_i
            end

            # Fall back to minimal dev plans when cache is empty
            if (fallback_config = WithEntitlements::FALLBACK_PLANS[test_planid])
              val = fallback_config[:limits][key]
              return 0 if val.nil?
              return Float::INFINITY if val == 'unlimited'

              return val.to_i
            end

            0
          end

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
