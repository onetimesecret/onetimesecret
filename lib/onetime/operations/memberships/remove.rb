# lib/onetime/operations/memberships/remove.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model and the shared guard explicitly.
require 'onetime/models/admin_audit_event'
require_relative 'support'

module Onetime
  module Operations
    module Memberships
      # Remove a member from an organization — the SINGLE implementation of the
      # membership remove verb (#3731). The colonel endpoint
      # (`DELETE /api/colonel/organizations/:org_id/members/:member_id`) and the
      # `bin/ots memberships remove` CLI are thin adapters over it.
      #
      # ## Removal primitive (tears down + clears materialized entitlements)
      #
      # Delegates to {OrganizationMembership#destroy_with_index_cleanup!}, which
      # clears the four materialized-entitlement sub-keys (materialized_entitlements,
      # entitlements_plan/grants/revokes) BEFORE destroying the through model, then
      # delegates the three-structure invariant to Familia's remove_members_instance
      # (ZREM from org.members, SREM the org from customer.participations, destroy the
      # hash). So the member's materialized entitlements are fully cleared on removal.
      #
      # ## Sole-owner guardrail
      #
      # Removing the last remaining owner is refused (`:last_owner`) so the org is
      # never orphaned. See {Memberships::Support#sole_owner?}.
      #
      # ## Audit
      #
      # A real removal records EXACTLY ONE {Onetime::AdminAuditEvent}. `:not_found`
      # and `:last_owner` mutate and audit NOTHING. No dry_run: removal has no plan
      # to preview; the confirmation lives in the adapters.
      class Remove
        include Memberships::Support

        AUDIT_VERB = 'membership.remove'

        # @!attribute status [r] Symbol — :success | :not_found | :last_owner
        Result = Data.define(:status, :org_id, :customer_id, :role)

        # @param org [Onetime::Organization] target org (caller resolves; required).
        # @param customer [Onetime::Customer] the member to remove.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        def initialize(org:, customer:, actor:)
          @org      = org
          @customer = customer
          @actor    = actor
        end

        # @return [Result]
        def call
          # No active? gate is needed (unlike SetRole): find_by_org_customer only
          # returns active, composite-keyed memberships — pending invites are
          # UUID-keyed with customer_objid=nil and never match here. Non-nil ⟹ active.
          membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @customer.objid)
          return build(:not_found, nil) unless membership

          return build(:last_owner, membership.role) if sole_owner?(@org, membership)

          removed_role = membership.role
          membership.destroy_with_index_cleanup!

          # One audit event per real removal, emitted from the op (adapters MUST
          # NOT audit). Public ids only; no secret detail.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { org_id: @org.extid },
          )

          build(:success, removed_role)
        end

        private

        def build(status, role)
          Result.new(
            status: status,
            org_id: @org.extid,
            customer_id: @customer.extid,
            role: role,
          )
        end
      end
    end
  end
end
