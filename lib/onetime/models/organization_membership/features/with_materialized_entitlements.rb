# lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb
#
# frozen_string_literal: true

module Onetime
  module Models
    module Features
      # Membership-Level Materialized Entitlement Feature (ADR-012 Stage 3)
      #
      # Extends OrganizationMembership with the same materialization storage
      # that organizations use, enabling role-aware entitlement checks.
      #
      # Materialization formula:
      #   membership.entitlements = org.materialized_entitlements ∩ ROLE_ENTITLEMENTS[role]
      #
      # The intersection ensures a membership never exceeds its org's plan,
      # while ROLE_ENTITLEMENTS restricts which plan entitlements the role
      # template permits.
      #
      # Fields (same as Organization's WithMaterializedEntitlements):
      # - entitlements_plan: Set populated by materialize_for_role!
      # - entitlements_grants: Operator-added entitlements (per-member overrides)
      # - entitlements_revokes: Operator-removed entitlements (per-member overrides)
      # - materialized_entitlements: Effective set after reconciliation
      # - materialized_entitlements_at: Timestamp + content hash
      #
      # Reconciliation order: entitlements_plan + grants - revokes
      #
      # Usage:
      #   membership.materialize_for_role!         # computes from org + role
      #   membership.can?('custom_domains')        # => true/false
      #   membership.entitlements                  # => ["api_access", ...]
      #
      module MembershipMaterializedEntitlements
        Familia::Base.add_feature self, :membership_materialized_entitlements

        # Compute content hash for entitlement set (for staleness detection)
        # Defined at module level for testability.
        #
        # @param entitlements [Array<String>] Entitlement strings
        # @return [String] Short hash of sorted, joined entitlements
        def self.entitlements_content_hash(entitlements)
          content = entitlements.sort.join(',')
          Digest::SHA256.hexdigest(content)[0, 12]
        end

        def self.included(base)
          OT.ld "[features] #{base}: #{name}" if defined?(OT)

          base.include InstanceMethods
          base.extend ClassMethods

          # Role-derived entitlements (computed from org ∩ role template)
          base.set :entitlements_plan

          # Operator overrides (grants add, revokes remove at membership level)
          base.set :entitlements_grants
          base.set :entitlements_revokes

          # Effective entitlements after reconciliation
          base.set :materialized_entitlements

          # Materialization metadata: "timestamp:content_hash"
          base.field :materialized_entitlements_at
        end

        module ClassMethods
          # Forward to module-level method for consistency
          def entitlements_content_hash(entitlements)
            MembershipMaterializedEntitlements.entitlements_content_hash(entitlements)
          end
        end

        module InstanceMethods
          # Materialize entitlements for this membership based on role.
          #
          # Computes: org.materialized_entitlements ∩ ROLE_ENTITLEMENTS[role]
          # Writes to entitlements_plan, then reconciles via apply_entitlements.
          #
          # Called from:
          # - activate! (invite acceptance)
          # - ensure_membership (SSO first-auth)
          # - Role change
          # - Org plan change (via background job re-materializing all members)
          #
          # @return [Boolean] True if materialization succeeded
          def materialize_for_role!
            org = organization
            return false unless org

            current_role  = role || 'member'
            role_template = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS[current_role]
            return false unless role_template

            # Intersection: org's materialized_entitlements ∩ role template
            # This ensures membership never exceeds org's plan (ADR-012 Stage 3)
            org_entitlements       = org.materialized_entitlements.to_set
            effective_entitlements = (org_entitlements & role_template).to_a

            # Compute content hash and set metadata
            content_hash                      = self.class.entitlements_content_hash(effective_entitlements)
            self.materialized_entitlements_at = "#{Familia.now.to_i}:#{content_hash}"

            # Save scalar, then execute collection operations
            save_with_collections do
              entitlements_plan.clear
              effective_entitlements.each { |e| entitlements_plan.add(e) }
              apply_entitlements
            end
          end

          # Reconcile effective entitlements from sources
          #
          # Order: entitlements_plan + entitlements_grants - entitlements_revokes
          #
          # Wraps the write operations in MULTI/EXEC via Familia#transaction.
          # Source-set reads happen BEFORE the transaction.
          #
          # @return [Array<String>] Effective entitlements after reconciliation
          def apply_entitlements
            # Snapshot source sets outside the transaction
            plan_members   = entitlements_plan.to_a
            grant_members  = entitlements_grants.to_a
            revoke_members = entitlements_revokes.to_a

            transaction do
              materialized_entitlements.clear
              plan_members.each   { |e| materialized_entitlements.add(e) }
              grant_members.each  { |e| materialized_entitlements.add(e) }
              revoke_members.each { |e| materialized_entitlements.remove_element(e) }
            end

            materialized_entitlements.to_a
          end

          # Check if entitlements are materialized
          #
          # @return [Boolean] True if entitlements have been materialized
          def entitlements_materialized?
            !materialized_entitlements_at.to_s.empty?
          end

          # Get effective entitlements for this membership.
          #
          # If materialized, returns from materialized_entitlements.
          # Otherwise, computes on-the-fly from org ∩ role (fallback for
          # memberships created before materialization was wired in).
          #
          # @return [Array<String>] List of entitlement strings
          def entitlements
            if entitlements_materialized?
              return materialized_entitlements.to_a
            end

            # Fallback: compute from org + role without persisting
            compute_entitlements_from_role
          end

          # Check if membership has a specific entitlement
          #
          # @param entitlement [String, Symbol] Entitlement to check
          # @return [Boolean] True if membership has the entitlement
          def can?(entitlement)
            entitlements.include?(entitlement.to_s)
          end

          # Grant an entitlement to this membership (operator override)
          #
          # @param entitlement [String] Entitlement to grant
          # @return [Boolean] True if added (false if already present)
          def grant_entitlement(entitlement)
            ent    = entitlement.to_s
            entitlements_revokes.remove_element(ent)
            result = entitlements_grants.add(ent)
            apply_entitlements
            result
          end

          # Revoke an entitlement from this membership (operator override)
          #
          # @param entitlement [String] Entitlement to revoke
          # @return [Boolean] True if added (false if already present)
          def revoke_entitlement(entitlement)
            ent    = entitlement.to_s
            entitlements_grants.remove_element(ent)
            result = entitlements_revokes.add(ent)
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

          private

          # Compute entitlements from org + role without persisting.
          # Used as fallback for unmaterialized memberships.
          #
          # @return [Array<String>] Computed entitlements
          def compute_entitlements_from_role
            org = organization
            return [] unless org

            current_role  = role || 'member'
            role_template = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS[current_role]
            return [] unless role_template

            org_entitlements = org.materialized_entitlements.to_set
            (org_entitlements & role_template).to_a
          end
        end
      end
    end
  end
end
