# lib/onetime/operations/memberships/add.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

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
      # EXACTLY ONE {Onetime::ColonelAuditEvent}. A repeat-add attempt is STILL
      # recorded under the same verb with `outcome: 'no_change'` (#4337) — the
      # mutation is skipped, the attempt is not.
      #
      # ## Refusals audit too
      #
      # `:invalid_role` records one `result: :failure` event, and so does any
      # raise out of `ensure_membership` / `change_role!` (via
      # {Onetime::AuditedFailure}) — the success-path record sits after both, so
      # a failed add would otherwise leave no trace at all. `:no_change` is NOT a
      # refusal: the customer is already a member, which is the requested end
      # state.
      class Add
        include Onetime::AuditedFailure

        AUDIT_VERB = 'membership.add'

        # See {SetRole::REFUSAL_STATUSES}. `ensure_membership` failure is a raise
        # (Onetime::Problem), not a status, so it is covered by the macro below.
        REFUSAL_STATUSES = [:invalid_role].freeze

        # ensure_membership / change_role! raise on datastore or materialization
        # failure, BEFORE the success-path record. Records one `result: :failure`
        # and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @customer&.extid }

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
            existing     = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @customer.objid)
            current_role = existing&.role.to_s
            # An active membership with a blank role is a data-integrity anomaly:
            # the :no_change Result would then echo the REQUESTED role, masking the
            # corruption. Surface it in the log rather than silently papering over.
            if existing && current_role.empty?
              OT.le '[Memberships::Add] active membership has blank role ' \
                    "org=#{@org.extid} member=#{@customer.extid}"
            end
            role         = current_role.empty? ? @role : current_role
            record_no_change_event(role)
            return build(:no_change, role)
          end

          membership = Onetime::OrganizationMembership.ensure_membership(@org, @customer, role: @role)
          raise Onetime::Problem, 'Failed to create membership record' unless membership

          # Converge an activated-invitation role to the operator's explicit
          # request (re-materializes so entitlement checks are correct).
          membership.change_role!(@role) if membership.role.to_s != @role

          # One audit event per real add, emitted from the op (adapters MUST NOT
          # audit). Public ids only; no secret detail.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { role: membership.role, org_id: @org.extid },
          )

          build(:success, membership.role)
        end

        private

        # Single exit point for every non-success status, so the refusal audit
        # cannot be forgotten at an early return.
        def build(status, role)
          record_refusal(status, role) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            org_id: @org.extid,
            customer_id: @customer.extid,
            role: role,
          )
        end

        # A LIVE no-change attempt (#4337) — the OPERATOR trail. Adding a
        # customer who is already a member mutates nothing, but it is the same
        # reach as a real add, and the trail should not go quiet for it. Same
        # verb and target as the applied event; detail mirrors its shape (the
        # member's CURRENT role — the one the Result echoes — plus org_id) with
        # the `outcome: 'no_change'` marker. NOT fail-closed: nothing moved.
        # No local rescue — `record` is best-effort and swallows its own errors.
        def record_no_change_event(role)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: { outcome: 'no_change', role: role, org_id: @org.extid },
          )
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        def record_refusal(status, role)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :failure,
            detail: { reason: status.to_s, role: role, org_id: @org.extid },
          )
        rescue StandardError => ex
          OT.le "[Memberships::Add] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end
