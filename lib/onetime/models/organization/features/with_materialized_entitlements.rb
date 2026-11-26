# lib/onetime/models/organization/features/with_materialized_entitlements.rb
#
# frozen_string_literal: true

require_relative '../../features/entitlement_set_operations'

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

        # Compute content hash for a full materialized snapshot (entitlements + limits).
        # The org materializes both, so staleness detection must cover both — otherwise
        # plan edits that only touch limits look "fresh."
        #
        # When limits are empty/nil the result equals entitlements_content_hash, so
        # orgs on limits-free plans stay fresh across this change.
        #
        # @param entitlements [Array<String>, Enumerable] Entitlement strings
        # @param limits [Hash, nil] Flattened limits (e.g., {"teams.max" => "5"})
        # @return [String] 12-char hex hash
        def self.snapshot_content_hash(entitlements, limits = nil)
          ent_part = entitlements.to_a.sort.join(',')
          limits_h = limits ? limits.to_h : {}
          return Digest::SHA256.hexdigest(ent_part)[0, 12] if limits_h.empty?

          limits_part = limits_h
            .map { |k, v| [k.to_s, v.to_s] }
            .sort
            .map { |k, v| "#{k}=#{v}" }
            .join(',')
          Digest::SHA256.hexdigest("#{ent_part}|#{limits_part}")[0, 12]
        end

        def self.included(base)
          OT.ld "[features] #{base}: #{name}"

          base.include InstanceMethods
          base.extend ClassMethods

          # Plan-derived entitlements (copied from Billing::Plan at materialization)
          base.set :entitlements_plan

          # Plan-derived limits (copied from Billing::Plan at materialization)
          # Flattened keys: "teams.max" => "5", "secret_lifetime.max" => "unlimited"
          # NOTE: storage decl lives here because materialize_entitlements_from_plan
          # and materialize_entitlements_from_config (below) write to it.
          # The reader (`materialized_limit_for`) lives in WithMaterializedLimits.
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

          def snapshot_content_hash(entitlements, limits = nil)
            WithMaterializedEntitlements.snapshot_content_hash(entitlements, limits)
          end
        end

        module InstanceMethods
          include EntitlementSetOperations

          # Materialize entitlements from a plan
          #
          # Copies plan's entitlements and limits to org-local storage,
          # runs reconciliation, and stamps the applied_at field.
          #
          # Uses save_with_collections to ensure scalar fields persist before
          # collection operations run. If save fails, collections are untouched.
          #
          # @param plan [Billing::Plan] Plan to materialize from
          # @return [Boolean] True if materialization succeeded
          def materialize_entitlements_from_plan(plan)
            # Hash covers entitlements + limits — both are part of the materialized
            # snapshot, so a limits-only plan change must mark the org stale.
            content_hash                      = self.class.snapshot_content_hash(
              plan.entitlements.to_a,
              plan.limits.hgetall,
            )
            self.materialized_entitlements_at = "#{Familia.now.to_i}:#{content_hash}"

            # Save scalar, then execute collection operations
            save_with_collections do
              # Copy plan entitlements to org
              entitlements_plan.clear
              plan.entitlements.each { |e| entitlements_plan.add(e) }

              # Copy plan limits to org
              limits_plan.clear
              plan.limits.hgetall.each { |k, v| limits_plan[k] = v }

              # Reconcile: plan + grants - revokes
              apply_entitlements
            end
          end

          # Materialize entitlements from config-only plan data
          #
          # Used for plans that only exist in billing.yaml (e.g., free_v1).
          #
          # Uses save_with_collections to ensure scalar fields persist before
          # collection operations run. If save fails, collections are untouched.
          #
          # @param plan_data [Hash] Plan data from Billing::Plan.load_from_config
          # @return [Boolean] True if materialization succeeded
          def materialize_entitlements_from_config(plan_data)
            entitlements = plan_data[:entitlements] || []
            limits       = plan_data[:limits] || {}

            # Hash covers entitlements + limits (see materialize_entitlements_from_plan).
            content_hash                      = self.class.snapshot_content_hash(entitlements, limits)
            self.materialized_entitlements_at = "#{Familia.now.to_i}:#{content_hash}"

            # Save scalar, then execute collection operations
            save_with_collections do
              # Copy entitlements
              entitlements_plan.clear
              entitlements.each { |e| entitlements_plan.add(e) }

              # Copy limits
              limits_plan.clear
              limits.each { |k, v| limits_plan[k] = v.to_s }

              # Reconcile
              apply_entitlements
            end
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
            dbclient = Familia.dbclient

            # Start with org's materialized entitlements
            base = if entitlements_materialized?
                     materialized_entitlements.to_a
                   else
                     # Fallback for unmaterialized orgs
                     entitlements_plan.to_a
                   end

            # Apply session revokes (removes test plan's "reset" of current entitlements)
            if session_revokes_key && dbclient.exists?(session_revokes_key)
              session_revokes = dbclient.smembers(session_revokes_key)
              base           -= session_revokes
            end

            # Apply session grants (adds test plan entitlements)
            if session_grants_key && dbclient.exists?(session_grants_key)
              session_grants = dbclient.smembers(session_grants_key)
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
          # @param plan [Billing::Plan, Hash] Plan object or config hash to compare against
          # @return [Boolean] True if content hash differs
          def entitlements_stale?(plan)
            applied = materialized_entitlements_at_parsed
            return true unless applied

            # Handle both Plan objects and config Hashes
            if plan.respond_to?(:entitlements)
              entitlements = plan.entitlements.to_a
              limits       = plan.limits.hgetall
            else
              entitlements = plan[:entitlements] || []
              limits       = plan[:limits] || {}
            end
            current_hash = self.class.snapshot_content_hash(entitlements, limits)
            applied[:content_hash] != current_hash
          end
        end
      end
    end
  end
end
