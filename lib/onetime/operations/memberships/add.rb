# lib/onetime/operations/memberships/add.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model explicitly.
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Memberships
      # Add a known customer to an organization — the SINGLE implementation of the
      # membership add verb (#3731). The colonel endpoint
      # (`POST /api/colonel/organizations/:org_id/members`) and the
      # `bin/ots memberships add` CLI are thin adapters over it.
      #
      # ## Add + materialize (the canonical flow)
      #
      # Delegates to {OrganizationMembership.ensure_membership}, the canonical
      # "add a known customer" path: it activates a pending invitation if one
      # exists, otherwise direct-adds, and materializes entitlements in BOTH
      # branches. Materialization is mandatory — a bare `add_members_instance`
      # sets only the role LABEL, leaving `can?('manage_org')` false for an
      # owner/admin.
      #
      # ## Role convergence
      #
      # `ensure_membership` activates a pending invitation using the INVITATION's
      # stored role, which may differ from the operator's explicit `role:`. For a
      # fresh add we converge to the requested role via `change_role!` (which
      # re-materializes), so `add ORG CUST --role admin` reliably lands `admin`.
      #
      # ## Idempotency (add is strictly additive)
      #
      # If the customer is ALREADY a member, this returns `:no_change` and does
      # NOT touch their role — even when `role:` differs. Role changes are the
      # {SetRole} op's job; folding a demote/promote into "add" would let an add
      # silently demote the last owner. The Result carries the member's CURRENT
      # role so the adapter can point the operator at set-role. A real add records
      # EXACTLY ONE {Onetime::AdminAuditEvent}; a `:no_change` audits nothing.
      class Add
        AUDIT_VERB = 'membership.add'

        # Sourced from the model constant (never a hardcoded fork).
        VALID_ROLES = Onetime::OrganizationMembership::ROLE_ENTITLEMENTS.keys.freeze

        # @!attribute status [r] Symbol —
        #   :success | :no_change | :invalid_role
        Result = Data.define(:status, :org_id, :customer_id, :role)

        # @param org [Onetime::Organization] target org (caller resolves; required).
        # @param customer [Onetime::Customer] the customer to add (must already
        #   have an account — this op does not create invitations).
        # @param role [String, Symbol] role for a fresh add (default 'member').
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        def initialize(org:, customer:, actor:, role: 'member')
          @org      = org
          @customer = customer
          @role     = role.to_s
          @actor    = actor
        end

        # @return [Result]
        def call
          return build(:invalid_role, @role) unless VALID_ROLES.include?(@role)

          if @org.member?(@customer)
            existing = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @customer.objid)
            return build(:no_change, existing&.role || @role)
          end

          membership = Onetime::OrganizationMembership.ensure_membership(@org, @customer, role: @role)
          raise Onetime::Problem, 'Failed to create membership record' unless membership

          # Converge an activated-invitation role to the operator's explicit
          # request (re-materializes so entitlement checks are correct).
          membership.change_role!(@role) if membership.role.to_s != @role

          # One audit event per real add, emitted from the op (adapters MUST NOT
          # audit). Public ids only; no secret detail.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { role: membership.role, org_id: @org.extid },
          )

          build(:success, membership.role)
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
