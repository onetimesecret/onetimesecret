# lib/onetime/operations/memberships/set_role.rb
#
# frozen_string_literal: true

# Loaded at the call site (colonel logic + CLI), which run outside the app
# autoloaders — require the audit model and the shared guard explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
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
      # A real change records EXACTLY ONE {Onetime::ColonelAuditEvent}. An
      # idempotent `:no_change` (already at the target role) mutates nothing but
      # records one too (#4337), under the same verb with
      # `outcome: 'no_change'` — the org-scoped twin of
      # {Auth::Operations::Customers::SetRole}: reaching for `owner` on a
      # membership that already holds it is the same reach for the same
      # privilege, and the trail should not go quiet for it.
      #
      # A REFUSED change (`:invalid_role` / `:not_found` / `:last_owner`) records
      # exactly one `result: :failure` event — the operator attempted a privileged
      # mutation and was refused, which belongs in the trail for the same reason
      # {Auth::Operations::Customers::SetSuspension}'s raising privilege guard does.
      # Whether a refusal comes back as a Result or as an exception is an
      # implementation detail; the audit trail must not depend on it. `:no_change`
      # is deliberately NOT a refusal: nothing was attempted that could fail.
      #
      # ## Sole-owner guardrail
      #
      # Demoting the last remaining owner is refused (`:last_owner`) so the org is
      # never orphaned. See {Memberships::Support#sole_owner?}.
      class SetRole
        include Memberships::Support
        include Onetime::AuditedFailure
        include Onetime::AuditReason

        AUDIT_VERB = 'membership.set_role'

        # Statuses meaning "a privileged mutation was asked for and refused".
        # Each records one `result: :failure` event via {#build}. `:success` and
        # `:no_change` are excluded — each audits its own `result: :success`
        # event instead, the latter marked `outcome: 'no_change'`.
        REFUSAL_STATUSES = [:invalid_role, :not_found, :last_owner].freeze

        # change_role! / save can raise (datastore, materialization), and the
        # success-path record sits after them — so without this a blown-up role
        # change leaves no trace. Records one `result: :failure` and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @customer&.extid }

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
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338),
        #   recorded in the detail of the applied event AND the no-change one.
        #   Blank is treated as absent and both keep their pre-#4338 shape. NOT
        #   carried on the refusal event, whose `reason` key already means the
        #   refusal STATUS (see {#record_refusal}). See {Onetime::AuditReason}
        #   for the bound and the optional-now / required-later rollout.
        def initialize(org:, customer:, new_role:, actor:, reason: nil)
          @org      = org
          @customer = customer
          @new_role = new_role.to_s
          @actor    = actor
          @reason   = normalize_reason(reason)
        end

        # @return [Result]
        def call
          return build(:invalid_role, nil, @new_role) unless VALID_ROLES.include?(@new_role)

          membership = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @customer.objid)
          return build(:not_found, nil, @new_role) unless membership&.active?

          from = membership.role.to_s
          if from == @new_role
            record_no_change_event(from)
            return build(:no_change, from, from)
          end

          # Guardrail: never demote the sole remaining owner (would orphan the org).
          if from == 'owner' && sole_owner?(@org, membership)
            return build(:last_owner, from, @new_role)
          end

          # change_role! re-materializes entitlements (the whole point of #3731)
          # and PERSISTS the role field itself (via materialize_for_role!). The
          # save below is solely to stamp updated_at — not to persist the role.
          membership.change_role!(@new_role)
          membership.updated_at = Familia.now.to_f
          membership.save

          # One audit event per real change, emitted from the op (adapters MUST NOT
          # audit — avoids a double trail). Public ids only; no secret detail.
          #
          # FAIL-CLOSED (#4333): the org-scoped twin of customer.set_role — the
          # membership stores only the role it now holds, so the previous role
          # and the granting operator exist nowhere else. #record_refusal stays
          # fail-open: a refusal mutated nothing.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: with_reason(from: from, to: @new_role, org_id: @org.extid),
            fail_closed: true,
          )

          build(:success, from, @new_role)
        end

        private

        # A no-change attempt (#4337) — the OPERATOR trail, not the observation
        # trail. Same verb, target and detail keys as the applied event, with
        # `outcome: 'no_change'` marking it, so a filter on
        # `membership.set_role` shows every attempt against a membership rather
        # than only the ones that moved. NOT fail-closed: no privilege moved,
        # so there is no untraceable grant for a hard failure to surface. The
        # operator's `reason` (#4338) rides here too — an attempted-but-no-op
        # reach for `owner` still has a why.
        def record_no_change_event(from)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: with_reason(outcome: 'no_change', from: from, to: @new_role, org_id: @org.extid),
          )
        end

        # Single exit point for every non-success status, so the refusal audit
        # cannot be forgotten at one of the four early returns.
        def build(status, from, to)
          record_refusal(status, from, to) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            org_id: @org.extid,
            customer_id: @customer.extid,
            from: from,
            to: to,
          )
        end

        # Same verb/target/actor as the success event so a filter on
        # `membership.set_role` shows the attempt alongside the completions.
        # Best-effort like every audit write: never break the op.
        #
        # NO operator `reason` here (#4338), deliberately: this detail's
        # `reason` key already names the REFUSAL STATUS and predates the
        # operator-reason feature. See {Remove#record_refusal} for the full
        # rationale — the two refusal paths share it.
        def record_refusal(status, from, to)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :failure,
            detail: { reason: status.to_s, from: from, to: to, org_id: @org.extid },
          )
        rescue StandardError => ex
          OT.le "[Memberships::SetRole] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end
