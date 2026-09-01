# lib/onetime/operations/memberships/remove.rb
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
      # A real removal records EXACTLY ONE {Onetime::ColonelAuditEvent}. `:not_found`
      # and `:last_owner` MUTATE nothing but each record one `result: :failure`
      # event: a refused removal is a privileged attempt that must be traceable,
      # exactly like the raising privilege guard in
      # {Auth::Operations::Customers::SetSuspension}. A raise out of
      # `destroy_with_index_cleanup!` records the same way via
      # {Onetime::AuditedFailure}. No dry_run: removal has no plan to preview; the
      # confirmation lives in the adapters.
      class Remove
        include Memberships::Support
        include Onetime::AuditedFailure
        include Onetime::AuditReason

        AUDIT_VERB = 'membership.remove'

        # See {SetRole::REFUSAL_STATUSES}.
        REFUSAL_STATUSES = [:not_found, :last_owner].freeze

        # destroy_with_index_cleanup! tears down four entitlement sub-keys and
        # three index structures; a partial failure leaves the org in an unknown
        # state, and the success-path record sits after it. Records one
        # `result: :failure` and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @customer&.extid }

        # @!attribute status [r] Symbol — :success | :not_found | :last_owner
        Result = Data.define(:status, :org_id, :customer_id, :role)

        # @param org [Onetime::Organization] target org (caller resolves; required).
        # @param customer [Onetime::Customer] the member to remove.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338),
        #   recorded in the SUCCESS event's detail. Blank is treated as absent
        #   and the detail keeps its pre-#4338 shape. NOT carried on the
        #   refusal event, whose `reason` key already means the refusal STATUS
        #   (see {#record_refusal}). See {Onetime::AuditReason} for the bound
        #   and the optional-now / required-later rollout.
        def initialize(org:, customer:, actor:, reason: nil)
          @org      = org
          @customer = customer
          @actor    = actor
          @reason   = normalize_reason(reason)
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
          #
          # FAIL-CLOSED (#4333): a close peer of the named revoke verbs — the
          # membership row is destroyed, so an unrecorded removal leaves nothing
          # to say the customer ever had access to this org. #record_refusal
          # stays fail-open: a refusal mutated nothing.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :success,
            detail: with_reason(org_id: @org.extid),
            fail_closed: true,
          )

          build(:success, removed_role)
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

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op.
        #
        # NO operator `reason` here (#4338), deliberately: this detail's
        # `reason` key already names the REFUSAL STATUS and predates the
        # operator-reason feature. One key cannot mean two things, and renaming
        # a shipped audit detail key to make room would break every reader
        # filtering on it. A refusal mutated nothing, so what a reviewer needs
        # from it is why the SYSTEM said no, which is what this records.
        def record_refusal(status, role)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @customer.extid,
            result: :failure,
            detail: { reason: status.to_s, role: role, org_id: @org.extid },
          )
        rescue StandardError => ex
          OT.le "[Memberships::Remove] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end
