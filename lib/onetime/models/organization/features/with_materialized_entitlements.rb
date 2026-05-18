# lib/onetime/models/organization/features/with_materialized_entitlements.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Materialized Entitlement State Feature
      #
      # Adds org-local entitlement storage and reconciliation.
      # Entitlements are materialized at webhook time, not resolved at read time.
      #
      # Fields:
      # - entitlements_plan: Set copied from Plan.entitlements at materialization
      # - limits_plan: Hash copied from Plan.limits at materialization
      # - entitlements_grants: Operator-added entitlements (overrides plan)
      # - entitlements_revokes: Operator-removed entitlements (overrides plan)
      # - materialized_entitlements: Effective set after reconciliation
      # - materialized_entitlements_at: Timestamp + content hash for staleness detection
      #
      # Reconciliation order: plan + grants - revokes
      #
      module WithMaterializedEntitlements
        Familia::Base.add_feature self, :with_materialized_entitlements

        # Compute content hash for entitlement set (for staleness detection)
        # Defined at module level for testability and use from instance methods.
        #
        # @param entitlements [Array<String>] Entitlement strings
        # @return [String] Short hash of sorted, joined entitlements
        def self.entitlements_content_hash(entitlements)
          content = entitlements.sort.join(',')
          Digest::SHA256.hexdigest(content)[0, 12]
        end

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          base.include InstanceMethods
          base.extend ClassMethods

          # Plan-derived entitlements (copied from Billing::Plan at materialization)
          base.set :entitlements_plan

          # Plan-derived limits (copied from Billing::Plan at materialization)
          # Flattened keys: "teams.max" => "5", "secret_lifetime.max" => "unlimited"
          base.hashkey :limits_plan

          # Operator overrides (grants add, revokes remove)
          base.set :entitlements_grants
          base.set :entitlements_revokes

          # Effective entitlements after reconciliation (plan + grants − revokes)
          # Pairs with `materialized_entitlements_at` for consistent naming.
          # The `entitlements` method in WithEntitlements reads from this set.
          base.set :materialized_entitlements

          # Materialization metadata: "timestamp:content_hash"
          # Used for staleness detection when plan definitions change
          base.field :materialized_entitlements_at
        end

        module ClassMethods
          # Forward to module-level method for consistency
          def entitlements_content_hash(entitlements)
            WithMaterializedEntitlements.entitlements_content_hash(entitlements)
          end
        end

        module InstanceMethods
          # Materialize entitlements from a plan
          #
          # Copies plan's entitlements and limits to org-local storage,
          # runs reconciliation, and stamps the applied_at field.
          #
          # @param plan [Billing::Plan] Plan to materialize from
          # @return [Boolean] True if materialization succeeded
          def materialize_entitlements_from_plan(plan)
            # Copy plan entitlements to org
            entitlements_plan.clear
            plan.entitlements.each { |e| entitlements_plan.add(e) }

            # Copy plan limits to org
            limits_plan.clear
            plan.limits.hgetall.each { |k, v| limits_plan[k] = v }

            # Reconcile: plan + grants - revokes
            apply_entitlements

            # Stamp with timestamp and content hash
            content_hash                      = self.class.entitlements_content_hash(plan.entitlements.to_a)
            self.materialized_entitlements_at = "#{Familia.now.to_i}:#{content_hash}"

            true
          end

          # Materialize entitlements from config-only plan data
          #
          # Used for plans that only exist in billing.yaml (e.g., free_v1).
          #
          # @param plan_data [Hash] Plan data from Billing::Plan.load_from_config
          # @return [Boolean] True if materialization succeeded
          def materialize_entitlements_from_config(plan_data)
            # Copy entitlements
            entitlements_plan.clear
            (plan_data[:entitlements] || []).each { |e| entitlements_plan.add(e) }

            # Copy limits
            limits_plan.clear
            (plan_data[:limits] || {}).each { |k, v| limits_plan[k] = v.to_s }

            # Reconcile
            apply_entitlements

            # Stamp
            content_hash                      = self.class.entitlements_content_hash(plan_data[:entitlements] || [])
            self.materialized_entitlements_at = "#{Familia.now.to_i}:#{content_hash}"

            true
          end

          # Reconcile effective entitlements from sources
          #
          # Order: entitlements_plan + entitlements_grants - entitlements_revokes
          #
          # Uses Redis set operations for atomicity.
          #
          # @return [Array<String>] Effective entitlements after reconciliation
          def apply_entitlements
            # Start with plan entitlements
            materialized_entitlements.clear
            entitlements_plan.each { |e| materialized_entitlements.add(e) }

            # Add grants
            entitlements_grants.each { |e| materialized_entitlements.add(e) }

            # Remove revokes
            entitlements_revokes.each { |e| materialized_entitlements.delete(e) }

            materialized_entitlements.to_a
          end

          # Get limit value from materialized limits
          #
          # @param key [String] Limit key (e.g., "teams.max")
          # @return [Numeric] Limit value, Float::INFINITY for "unlimited"
          def materialized_limit_for(key)
            val = limits_plan[key]
            return 0 if val.nil?

            val == 'unlimited' ? Float::INFINITY : val.to_i
          end

          # Reconcile entitlements with session-scoped overrides
          #
          # Used by test mode: computes effective entitlements by applying
          # session-scoped grants/revokes on top of org's materialized state.
          # Order: materialized - session_revokes + session_grants
          #
          # Revokes before grants enables "reset and substitute":
          # 1. session_revokes = org's current entitlements (removes all)
          # 2. session_grants = test plan entitlements (adds replacement)
          #
          # @param session_grants_key [String] Redis key for session grants set
          # @param session_revokes_key [String] Redis key for session revokes set
          # @return [Array<String>] Effective entitlements for this session
          def reconcile_with_session_overrides(session_grants_key, session_revokes_key)
            redis = Familia.redis

            # Start with org's materialized entitlements
            base = if entitlements_materialized?
                     materialized_entitlements.to_a
                   else
                     # Fallback for unmaterialized orgs
                     entitlements_plan.to_a
                   end

            # Apply session revokes (removes test plan's "reset" of current entitlements)
            if session_revokes_key && redis.exists?(session_revokes_key)
              session_revokes = redis.smembers(session_revokes_key)
              base           -= session_revokes
            end

            # Apply session grants (adds test plan entitlements)
            if session_grants_key && redis.exists?(session_grants_key)
              session_grants = redis.smembers(session_grants_key)
              base          |= session_grants
            end

            base
          end

          # Check if entitlements are materialized
          #
          # @return [Boolean] True if entitlements have been materialized
          def entitlements_materialized?
            !materialized_entitlements_at.to_s.empty?
          end

          # Parse materialized_entitlements_at into components
          #
          # @return [Hash, nil] { timestamp:, content_hash: } or nil if not set
          def materialized_entitlements_at_parsed
            return nil if materialized_entitlements_at.to_s.empty?

            parts = materialized_entitlements_at.to_s.split(':')
            return nil unless parts.length == 2

            {
              timestamp: parts[0].to_i,
              content_hash: parts[1],
            }
          end

          # Check if materialized entitlements are stale vs a plan
          #
          # @param plan [Billing::Plan] Plan to compare against
          # @return [Boolean] True if content hash differs
          def entitlements_stale?(plan)
            applied = materialized_entitlements_at_parsed
            return true unless applied

            current_hash = self.class.entitlements_content_hash(plan.entitlements.to_a)
            applied[:content_hash] != current_hash
          end

          # Grant an entitlement to this org (operator override)
          #
          # @param entitlement [String] Entitlement to grant
          # @return [Boolean] True if added (false if already present)
          def grant_entitlement(entitlement)
            ent    = entitlement.to_s
            # Remove from revokes if present (grant takes precedence)
            entitlements_revokes.delete(ent)
            # Add to grants
            result = entitlements_grants.add(ent)
            # Reconcile
            apply_entitlements
            result
          end

          # Revoke an entitlement from this org (operator override)
          #
          # @param entitlement [String] Entitlement to revoke
          # @return [Boolean] True if added (false if already present)
          def revoke_entitlement(entitlement)
            ent    = entitlement.to_s
            # Remove from grants if present (explicit revoke)
            entitlements_grants.delete(ent)
            # Add to revokes
            result = entitlements_revokes.add(ent)
            # Reconcile
            apply_entitlements
            result
          end

          # Clear all operator overrides
          #
          # @return [Array<String>] Effective entitlements after clearing
          def clear_entitlement_overrides
            entitlements_grants.clear
            entitlements_revokes.clear
            apply_entitlements
          end
        end
      end
    end
  end
end
