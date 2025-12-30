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
      #   org.can?('custom_domains')        # => true/false
      #   org.entitlements                  # => ["api_access", "custom_domains", ...]
      #   org.limit_for('teams')            # => 1 (or Float::INFINITY)
      #   org.check_entitlement('api_access') # => {allowed: false, upgrade_needed: true, ...}
      #
      # == Fail-Open / Fail-Closed Design
      #
      # This module implements a dual-mode authorization strategy to support both
      # self-hosted (open source) and SaaS deployments:
      #
      # === FAIL-OPEN (Self-Hosted / Standalone Mode)
      #
      # When billing is disabled or no entitlements exist, we allow unlimited
      # resource creation. This ensures self-hosted instances work without any
      # billing configuration. Conditions that trigger fail-open:
      # - billing_enabled? returns false
      # - No plan assigned (planid empty)
      # - entitlements array is empty
      #
      # Result: STANDALONE_ENTITLEMENTS (full access), limits return Float::INFINITY
      #
      # === FAIL-CLOSED (SaaS / Billing Enabled)
      #
      # When billing is properly configured, quota checks are strictly enforced.
      # Internal errors (Redis failures, missing plan data) should propagate as
      # exceptions rather than silently allowing resource creation. This protects
      # revenue and ensures plan limits are respected.
      #
      # Result: Plan-defined entitlements and limits, errors raise exceptions
      #
      # == Quota Enforcement Locations
      #
      # Quota checks using at_limit? occur in:
      # - CreateOrganization#check_organization_quota! (organization limits)
      # - CreateInvitation#check_member_quota! (member limits, see #2224)
      # - BaseSecretAction (secret lifetime limits via limit_for)
      #
      module WithEntitlements
        Familia::Base.add_feature self, :with_entitlements

        # Full entitlement set for standalone mode
        # When billing is disabled or plan cache is empty, users get full access
        STANDALONE_ENTITLEMENTS = %w[
          api_access custom_privacy_defaults extended_default_expiration
          custom_domains custom_branding branded_homepage
          incoming_secrets custom_mail_defaults
          manage_orgs manage_teams manage_members audit_logs
        ].freeze

        # Minimal FREE tier entitlements as fallback when billing is enabled
        # but plan cache is empty. This prevents showing "No features available"
        # and provides a safe degraded experience.
        #
        # These match the free_v1 plan in billing.yaml.
        FREE_TIER_ENTITLEMENTS = %w[
          create_secrets
          view_receipt
          api_access
        ].freeze

        # FREE tier default limits when cache is unavailable
        FREE_TIER_LIMITS = {
          'teams.max' => 0,
          'members_per_team.max' => 0,
          'secret_lifetime.max' => 604_800, # 7 days in seconds
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
          # Fallback hierarchy:
          # 1. If billing disabled (standalone mode) -> STANDALONE_ENTITLEMENTS (full access)
          # 2. If no planid set -> FREE_TIER_ENTITLEMENTS
          # 3. If plan found in cache -> plan.entitlements
          # 4. If plan not in cache, try billing.yaml config fallback
          # 5. Final fallback -> FREE_TIER_ENTITLEMENTS (prevents "No features" error)
          #
          # @example
          #   org.entitlements  # => ["api_access", "custom_domains", "manage_teams"]
          def entitlements
            # Colonel test mode override - check Thread.current set by middleware
            # Empty string should fall back to actual plan (same as nil)
            test_planid = Thread.current[:entitlement_test_planid]
            if test_planid && !test_planid.empty?
              return test_plan_entitlements(test_planid)
            end

            # Fail-open: self-hosted/standalone gets full access
            unless billing_enabled?
              return WithEntitlements::STANDALONE_ENTITLEMENTS.dup
            end

            # Billing enabled: org with no plan gets FREE tier
            if planid.to_s.empty?
              return WithEntitlements::FREE_TIER_ENTITLEMENTS.dup
            end

            # Try loading from Redis cache first
            plan = ::Billing::Plan.load(planid)
            if plan
              return plan.entitlements.to_a
            end

            # Plan not in cache - try billing.yaml config fallback
            config_plan = ::Billing::Plan.load_from_config(planid)
            if config_plan && config_plan[:entitlements]
              OT.ld "[WithEntitlements] Using config fallback for plan: #{planid}"
              return config_plan[:entitlements].dup
            end

            # Final fallback: FREE tier to avoid "No features available"
            OT.lw '[WithEntitlements] Plan cache miss, using FREE tier fallback', {
              planid: planid,
            }
            WithEntitlements::FREE_TIER_ENTITLEMENTS.dup
          end

          # Get limit for a specific resource
          #
          # @param resource [String, Symbol] Resource to check limit for
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          #
          # Fallback hierarchy:
          # 1. If billing disabled (standalone mode) -> Float::INFINITY (unlimited)
          # 2. If no planid set -> FREE_TIER_LIMITS
          # 3. If plan found in cache -> plan.limits
          # 4. If plan not in cache, try billing.yaml config fallback
          # 5. Final fallback -> FREE_TIER_LIMITS (conservative defaults)
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

            # Fail-open: self-hosted/standalone gets unlimited
            return Float::INFINITY unless billing_enabled?

            # Flattened key: "teams" => "teams.max"
            key = resource.to_s.include?('.') ? resource.to_s : "#{resource}.max"

            # Billing enabled: org with no plan gets FREE tier limits
            if planid.to_s.empty?
              return free_tier_limit_for(key)
            end

            # Try loading from Redis cache first
            plan = ::Billing::Plan.load(planid)
            if plan
              val = plan.limits[key]
              return parse_limit_value(val)
            end

            # Plan not in cache - try billing.yaml config fallback
            config_plan = ::Billing::Plan.load_from_config(planid)
            if config_plan && config_plan[:limits]
              val = config_plan[:limits][key]
              return parse_limit_value(val) unless val.nil?
            end

            # Final fallback: FREE tier limits
            free_tier_limit_for(key)
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
          # to billing.yaml config (for development when Stripe cache is empty).
          #
          # @param test_planid [String] Plan ID to test
          # @return [Array<String>] List of entitlements for the test plan
          def test_plan_entitlements(test_planid)
            # Check Billing::Plan cache first (production/Stripe-synced)
            plan = ::Billing::Plan.load(test_planid)
            return plan.entitlements.to_a if plan

            # Fall back to billing.yaml config when Stripe cache is empty
            config_plan = ::Billing::Plan.load_from_config(test_planid)
            return config_plan[:entitlements].dup if config_plan

            []
          end

          # Get limit for a resource from a test plan (colonel test mode)
          #
          # Checks Billing::Plan cache first (production/Stripe-synced), then falls back
          # to billing.yaml config (for development when Stripe cache is empty).
          #
          # @param test_planid [String] Plan ID to test
          # @param resource [String, Symbol] Resource to check limit for
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          def test_plan_limit_for(test_planid, resource)
            # Flattened key: "teams" => "teams.max"
            key = resource.to_s.include?('.') ? resource.to_s : "#{resource}.max"

            # Check Billing::Plan cache first (production/Stripe-synced)
            plan = ::Billing::Plan.load(test_planid)
            if plan
              limits_hash = plan.limits.hgetall || {}
              val         = limits_hash[key]
              return 0 if val.nil? || val.to_s.empty?
              return Float::INFINITY if val == 'unlimited'

              return val.to_i
            end

            # Fall back to billing.yaml config when Stripe cache is empty
            config_plan = ::Billing::Plan.load_from_config(test_planid)
            if config_plan
              val = config_plan[:limits][key]
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

          # Get FREE tier limit for a resource key
          #
          # @param key [String] Flattened limit key (e.g., "teams.max")
          # @return [Numeric] Limit value, defaults to 0 for unknown keys
          def free_tier_limit_for(key)
            val = WithEntitlements::FREE_TIER_LIMITS[key]
            return 0 if val.nil?

            val
          end

          # Parse a limit value from string/nil to numeric
          #
          # @param val [String, Integer, nil] Raw limit value
          # @return [Numeric] Parsed limit (0, integer, or Float::INFINITY)
          def parse_limit_value(val)
            return 0 if val.nil? || val.to_s.empty?
            return Float::INFINITY if ['unlimited', '-1'].include?(val.to_s)

            val.to_i
          end
        end
      end
    end
  end
end
