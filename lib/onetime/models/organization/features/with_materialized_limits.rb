# lib/onetime/models/organization/features/with_materialized_limits.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Materialized Limits Feature (Organization-only)
      #
      # Owns the read-side of resource limits (e.g. teams.max, secret_lifetime.max).
      # The `limits_plan` hashkey itself is declared in WithMaterializedEntitlements
      # because materialization writers in that module populate it; this feature
      # provides the reader and the higher-level limit accessors that include the
      # Plan.load fallback chain.
      #
      # This module is Organization-specific because it references `planid`,
      # `Billing::Plan`, and the standalone-mode billing semantics. It depends on
      # WithEntitlements (for `billing_enabled?` and `parse_limit_value`) and on
      # WithPlanEntitlements (for `free_tier_limit_for`).
      #
      # == Fail-Open / Fail-Closed Design
      #
      # See WithPlanEntitlements for the full rationale. Mirrors that module's
      # dual-mode strategy for the limits side: standalone returns
      # Float::INFINITY; SaaS with unknown plan raises PlanCacheMissError.
      #
      module WithMaterializedLimits
        Familia::Base.add_feature self, :with_materialized_limits

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"
          base.include InstanceMethods
        end

        module InstanceMethods
          # Get limit value from materialized limits
          #
          # Reads the org-local `limits_plan` hashkey populated at
          # materialization time. The hashkey itself is declared in
          # WithMaterializedEntitlements (writer co-located with storage decl).
          #
          # @param key [String] Limit key (e.g., "teams.max")
          # @return [Numeric] Limit value, Float::INFINITY for "unlimited"
          def materialized_limit_for(key)
            val = limits_plan[key]
            return 0 if val.nil?

            val == 'unlimited' ? Float::INFINITY : val.to_i
          end

          # Get limit for a resource (org-scoped)
          #
          # @param resource [String, Symbol] Resource to check
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          #
          # Fallback hierarchy:
          # 1. If billing disabled (standalone mode) -> Float::INFINITY (unlimited)
          # 2. If materialized -> materialized_limit_for(key)
          # 3. If no planid set -> free_tier_limits
          # 4. If plan found in cache -> plan.limits
          # 5. If plan not in cache, try billing.yaml config fallback
          # 6. Final fallback -> raise PlanCacheMissError (fail-closed)
          #
          # @example
          #   org.limit_for('teams')            # => 1
          #   org.limit_for(:members_per_team)  # => Float::INFINITY
          #   org.limit_for('unknown')          # => 0
          def limit_for(resource)
            # Fail-open: self-hosted/standalone gets unlimited
            return Float::INFINITY unless billing_enabled?

            # Flattened key: "teams" => "teams.max"
            key = resource.to_s.include?('.') ? resource.to_s : "#{resource}.max"

            # Phase 2: Read from materialized org-local limits when available
            # Guard: check if WithMaterializedEntitlements is included
            if respond_to?(:entitlements_materialized?) && entitlements_materialized?
              return materialized_limit_for(key)
            end

            # Legacy path (migration): org hasn't been materialized yet
            if planid.to_s.empty?
              return free_tier_limit_for(key)
            end

            # Guard: Billing module may not be loaded. Fall through to fail-closed.
            if defined?(::Billing::Plan)
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
            end

            # Fail-closed: unknown plan ID is an ops problem, not a silent degradation.
            raise Billing::PlanCacheMissError.new(
              'Plan not found in cache or config',
              plan_id: planid,
              context: 'WithMaterializedLimits#limit_for',
              resource: key,
              organization_id: extid,
            )
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

          # Get limit with request context for preview mode support
          #
          # Call sites that have session access should use this method instead
          # of `limit_for` when preview mode needs to be respected.
          #
          # @param resource [String, Symbol] Resource to check limit for
          # @param session [Hash, nil] Rack session hash (or hash-like object)
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          #
          # @example Controller usage
          #   org.limit_for_request('teams', env['rack.session'])
          def limit_for_request(resource, session = nil)
            return limit_for(resource) unless session.respond_to?(:key?)

            preview_planid = session[:entitlement_preview_planid]

            if preview_planid && !preview_planid.to_s.empty?
              return test_plan_limit_for(preview_planid, resource)
            end

            limit_for(resource)
          end

          private

          # Get limit for a resource from a test plan (colonel test mode)
          #
          # Checks Billing::Plan cache first (production/Stripe-synced), then falls back
          # to billing.yaml config (for development when Stripe cache is empty).
          #
          # @param test_planid [String] Plan ID to test
          # @param resource [String, Symbol] Resource to check limit for
          # @return [Numeric] Limit value (Float::INFINITY for unlimited)
          def test_plan_limit_for(test_planid, resource)
            # Guard: billing must be enabled and Billing::Plan must exist
            return Float::INFINITY unless billing_enabled? && defined?(::Billing::Plan)

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
        end
      end
    end
  end
end
