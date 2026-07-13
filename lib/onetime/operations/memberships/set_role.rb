# lib/onetime/operations/memberships/set_role.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model and the shared guard explicitly.
require 'onetime/models/admin_audit_event'
require_relative 'support'

module Onetime
  module Operations
    module Memberships
      # Change an organization member's role — the SINGLE implementation of the
      # membership set-role verb (#3731). The colonel endpoint
      # (`POST /api/colonel/organizations/:org_id/members/:member_id/role`) and the
      # `bin/ots memberships set-role` CLI are thin adapters over it.
      #
      # ## Why the op owns the role change
      #
      # A role change MUST go through {OrganizationMembership#change_role!} — the
      # only path that re-materializes entitlements. Setting the role label alone
      # leaves `can?('manage_org')` (and every other role-gated entitlement) stale,
      # which is the exact defect this issue exists to prevent. Both adapters call
      # this op so neither can bypass materialization.
      #
      # ## Exactly-once audit + no-op semantics
      #
      # A real change records EXACTLY ONE {Onetime::AdminAuditEvent}. An idempotent
      # `:no_change` (already at the target role) mutates and audits NOTHING.
      #
      # ## Sole-owner guardrail
      #
      # Demoting the last remaining owner is refused (`:last_owner`) so the org is
      # never orphaned. See {Memberships::Support#sole_owner?}.
      class SetRole
        include Memberships::Support

        AUDIT_VERB = 'membership.set_role'

        # Assignable roles — sourced from the model constant (never a hardcoded
        # fork), so owner/admin/member stay in lockstep with ROLE_ENTITLEMENTS.
        VALID_ROLES = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS.keys.freeze

        # @!attribute status [r] Symbol —
        #   :success | :no_change | :not_found | :invalid_role | :last_owner
        Result = Data.define(:status, :org_id, :customer_id, :from, :to)

        # @param org [Onetime::Organization] target org (caller resolves; required).
        # @param customer [Onetime::Customer] the member whose role changes.
        # @param new_role [String, Symbol] target role; must be in VALID_ROLES.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        def initialize(org:, customer:, new_role:, actor:)
          @org      = org
          @customer = customer
          @new_role = new_role.to_s
          @actor    = actor
        end

        # @return [Result]
        def call
          return build(:invalid_role, nil, @new_role) unless VALID_ROLES.include?(@new_role)

          membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @customer.objid)
          return build(:not_found, nil, @new_role) unless membership&.active?

          from = membership.role.to_s
          return build(:no_change, from, from) if from == @new_role

          # Guardrail: never demote the sole remaining owner (would orphan the org).
          if from == 'owner' && sole_owner?(@org, membership)
            return build(:last_owner, from, @new_role)
          end

          # change_role! re-materializes entitlements (the whole point of #3731).
          membership.change_role!(@new_role)
          membership.updated_at = Familia.now.to_f
          membership.save

          # One audit event per real change, emitted from the op (adapters MUST NOT
          # audit — avoids a double trail). Public ids only; no secret detail.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { from: from, to: @new_role, org_id: @org.extid },
          )

          build(:success, from, @new_role)
        end

        private

        def build(status, from, to)
          Result.new(
            status: status,
            org_id: @org.extid,
            customer_id: @customer.extid,
            from: from,
            to: to,
          )
        end
      end
    end
  end
end
