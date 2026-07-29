# lib/onetime/operations/org/transfer_ownership.rb
#
# frozen_string_literal: true

# Loaded at the call site (CLI today, a colonel endpoint later), which run
# outside the app autoloaders — require the audit model and the composed
# membership op explicitly.
require 'onetime/models/admin_audit_event'
require 'onetime/audited_failure'
require_relative '../memberships/set_role'

module Onetime
  module Operations
    module Org
      # Transfer an organization's ownership to an existing active member — the
      # SINGLE implementation of the admin transfer verb (#3731).
      #
      # Adapters:
      #   - `bin/ots org transfer-ownership ORG NEW_OWNER`
      #   - (future) `POST /api/colonel/organizations/:org_id/transfer-ownership`
      #     — D33 deliberately keeps the HTTP peer out of this change; the
      #     guardrail statuses below map cleanly onto raise_form_error when it
      #     lands. `apps/api/organizations/logic/members/update_member_role.rb`
      #     already tells end users to "transfer ownership", so the gap is real.
      #
      # ## Compose, do not reimplement
      #
      # BOTH role mutations go through {Onetime::Operations::Memberships::SetRole}
      # → {Onetime::OrganizationMembership#change_role!}, the only path that
      # re-materializes entitlements. This op contains no direct `membership.role=`
      # assignment: the promoted member must GAIN `manage_org` and the demoted
      # owner must LOSE it, and only materialize_for_role! makes that true.
      #
      # ## THE ORDER IS FORCED, NOT CHOSEN: promote, then demote
      #
      # SetRole refuses to demote a sole owner (`:last_owner`, see
      # {Onetime::Operations::Memberships::Support#sole_owner?}). At the start of
      # a transfer the outgoing owner IS the sole owner, so a demote-first
      # ordering deadlocks immediately. Promoting first also guarantees the org
      # has a live owner at every instant.
      #
      # The cost is a two-round-trip window in which the org carries TWO
      # `role: 'owner'` memberships and therefore transiently FAILS `bin/ots org
      # doctor` check 4 (`membership_role_sync`, which is explicitly
      # `repairable: false`). The window cannot be closed — every other ordering
      # is refused by the sole-owner guard.
      #
      # RECOVERY FROM A CRASH INSIDE THE WINDOW IS TO RE-RUN THIS OP, NOT THE
      # DOCTOR. This op is idempotent and demotes ALL other active owners, so a
      # second run finishes the job. `org doctor` cannot repair check 4.
      #
      # ## Audit (CONTRACT 4) — three events per transfer, by design (D26)
      #
      # This op records EXACTLY ONE {Onetime::AdminAuditEvent} ({AUDIT_VERB}).
      # The two composed SetRole calls each record their own
      # `membership.set_role` event, so a full transfer leaves three events. That
      # is deliberate: the sub-events make the trail replayable, and the
      # alternative (an audit-suppression flag on SetRole) introduces a
      # conditional-audit code path the house style has nowhere else. Adapters
      # MUST NOT audit.
      #
      # A FAILED transfer is audited symmetrically, and for the same reason it
      # emits multiple events: `:invalid_role`/`:not_member` each record one
      # `result: :failure`, and a raise out of apply! records one via
      # {Onetime::AuditedFailure}. `set_role!` raises a FRESH Onetime::Problem,
      # so SetRole's own refusal event and this op's failure event both land —
      # that is D26 applied to the failure path, not double-recording.
      #
      # ## Deliberate omissions — read these before "fixing" them
      #
      # - The new owner is NOT auto-added when they are not a member (D28):
      #   `:not_member`, and the adapter tells the operator to run
      #   `bin/ots memberships add` first. One confirmation must not both create
      #   a membership and hand it ownership.
      # - The outgoing owner is NOT removed (D27). `--demote-to` has no `remove`
      #   sentinel: removing them would break `bin/ots customers doctor` check 1
      #   for anyone whose `default_org_id` points at this org.
      # - `org.created_by` is NEVER written — immutable audit state (ADR-012,
      #   organization.rb:69). CONSEQUENCE (D32): `owner_id` and `created_by`
      #   permanently disagree on a transferred org, so the
      #   `standardize_owner_id` chore logs its Branch 3b warning for that org
      #   forever. That is expected, not a defect.
      # - Billing moves NOTHING. `stripe_customer_id`, `stripe_subscription_id`,
      #   `billing_email` and `email_hash` are ORGANIZATION fields
      #   (with_organization_billing.rb) — the subscription already belongs to the
      #   org, not to the owning customer. `billing_email` is additionally
      #   written FROM Stripe by the `customer.updated` webhook, so a local
      #   rewrite would be clobbered.
      # - `contact_email` is left alone: it is the org's identity in
      #   `contact_email_index`, and changing it means releasing and re-reserving
      #   an HSETNX slot. That is a separate verb.
      # - `org.rematerialize_all_memberships!` is NOT called. It exists for PLAN
      #   changes; the plan does not change here, and the only two memberships
      #   whose role moved were already re-materialized by `change_role!`.
      #
      # ## Constant-lookup discipline
      #
      # `Onetime::Operations::Billing` exists, so a bare constant inside this
      # namespace can resolve somewhere surprising and only intermittently.
      # Always fully qualify `Onetime::Organization` / `Onetime::Customer` /
      # `Onetime::OrganizationMembership` /
      # `Onetime::Operations::Memberships::SetRole` here (precedent:
      # memberships/set_role.rb:64).
      class TransferOwnership
        include Onetime::AuditedFailure

        # Full-noun subject, matching the rest of the admin trail
        # (`organization.create`, `organization.reconcile`).
        AUDIT_VERB = 'organization.transfer_ownership'

        # Roles the outgoing owner(s) may be demoted to. Sourced from SetRole's
        # own VALID_ROLES (never a hardcoded fork) minus 'owner': allowing
        # 'owner' would leave two owners behind and permanently trip doctor
        # check 4, i.e. it would not be a transfer at all.
        DEMOTABLE_ROLES = (
          Onetime::Operations::Memberships::SetRole::VALID_ROLES - ['owner']
        ).freeze

        # Statuses the adapters treat as "not a failure".
        OK_STATUSES = [:planned, :success, :no_change].freeze

        # The complement: a privileged mutation was asked for and REFUSED. Each
        # records one `result: :failure` event.
        REFUSAL_STATUSES = [:not_member, :invalid_role].freeze

        # apply! mutates in three steps and rolls back BEFORE re-raising, so a
        # blown-up transfer can leave the org with two owners (doctor check 4 is
        # `repairable: false`). The success record sits after apply!, so without
        # this the highest-blast-radius org verb fails silently. Records one
        # `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE and the success
        # event is applied-path-only.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @org&.extid },
          detail: -> { { dry_run: @dry_run, to: @new_owner&.extid } }

        # @!attribute status [r] Symbol —
        #   :planned (dry run) | :success | :no_change | :not_member | :invalid_role
        # @!attribute org_id [r] String — the org's PUBLIC extid.
        # @!attribute from_owner_id [r] String, nil — the outgoing owner's PUBLIC
        #   extid, or nil when `org.owner_id` resolved to no live customer
        #   (see +orphaned_owner+). Never an objid.
        # @!attribute from_owner_role_after [r] String — the role the outgoing
        #   owner(s) land on (the `demote_to` echo).
        # @!attribute to_owner_id [r] String — the new owner's PUBLIC extid.
        # @!attribute demoted [r] Array<String> — PUBLIC extids of the owner
        #   memberships demoted (on a dry run: that WOULD be demoted). Plural
        #   because the data model permits more than one owner membership (D29).
        # @!attribute orphaned_owner [r] Boolean — `org.owner_id` was blank or
        #   pointed at a deleted customer (`org doctor` check 1). D30: this does
        #   NOT block; the transfer proceeds and repairs it.
        # @!attribute dry_run [r] Boolean
        Result = Data.define(
          :status,
          :org_id,
          :from_owner_id,
          :from_owner_role_after,
          :to_owner_id,
          :demoted,
          :orphaned_owner,
          :dry_run,
        )

        # @param org [Onetime::Organization] resolved org (the adapter resolves).
        # @param new_owner [Onetime::Customer] resolved incoming owner. MUST
        #   already be an active member (ADR-023: real, not synthesized).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param demote_to [String] role for the outgoing owner(s); must be in
        #   {DEMOTABLE_ROLES}. Defaults to 'admin' (D27).
        # @param dry_run [Boolean] preview only when true (THE DEFAULT — this is
        #   a destructive verb, same posture as Domains::Transfer/Remove).
        def initialize(org:, new_owner:, actor:, demote_to: 'admin', dry_run: true)
          @org       = org
          @new_owner = new_owner
          @actor     = actor
          @demote_to = demote_to.to_s.strip.downcase
          @dry_run   = dry_run
        end

        # @return [Result]
        # @raise [Onetime::Problem] only when a mutation fails mid-apply, after a
        #   best-effort rollback and BEFORE any audit event is written.
        def call
          return build(:invalid_role) unless DEMOTABLE_ROLES.include?(@demote_to)

          target = Onetime::OrganizationMembership.find_by_org_customer(@org.objid, @new_owner.objid)
          return build(:not_member) unless target&.active?

          # Live authority is the membership set, NOT org.owner_id
          # (organization.rb:102-107 — owner_id is the deprecated mirror).
          outgoing = other_owner_memberships

          # Snapshot the legacy mirror before anything moves.
          original_owner_id = @org.owner_id.to_s
          resolved_owner    = original_owner_id.empty? ? nil : Onetime::Customer.load(original_owner_id)
          @orphaned_owner   = resolved_owner.nil?
          @from_owner_id    = resolved_owner&.extid

          # Fully idempotent: already the owner, the ONLY owner, and the legacy
          # mirror already agrees. A partial state (owner role but a stale
          # owner_id — the doctor's check-4 mismatch) deliberately does NOT
          # short-circuit here: it proceeds and repairs.
          if target.owner? && outgoing.empty? && original_owner_id == @new_owner.objid.to_s
            return build(:no_change, demoted: [])
          end

          planned = outgoing.filter_map { |membership| membership.customer&.extid }
          return build(:planned, demoted: planned) if @dry_run

          demoted = apply!(target, outgoing, original_owner_id)

          # Exactly one audit event per applied transfer, emitted here. PUBLIC
          # ids only — never objid/custid. The two composed SetRole calls emit
          # their own `membership.set_role` events (D26).
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @org.extid,
            result: :success,
            detail: {
              from: @from_owner_id,
              to: @new_owner.extid,
              demoted_to: @demote_to,
              demoted_count: demoted.size,
            },
          )

          OT.info "[Org::TransferOwnership] #{@org.extid} #{@from_owner_id || '(orphaned)'} -> " \
                  "#{@new_owner.extid} demoted=#{demoted.size} to=#{@demote_to}"

          build(:success, demoted: demoted)
        end

        private

        # Active owner memberships OTHER than the incoming owner's. D29: every
        # one of these is demoted — that is the only outcome that leaves the org
        # passing doctor check 4 (which is `repairable: false`, so anything left
        # behind needs a human forever).
        def other_owner_memberships
          Onetime::OrganizationMembership.active_for_org(@org).select do |membership|
            membership.owner? && membership.customer_objid.to_s != @new_owner.objid.to_s
          end
        end

        # The three mutation steps, in the ONE order the sole-owner guard permits.
        #
        # @return [Array<String>] extids actually demoted
        def apply!(target, outgoing, original_owner_id)
          # STEP 1 — PROMOTE FIRST. Mandatory: demoting first would hit the
          # sole-owner guard and return :last_owner.
          previous_target_role = promote!(target)

          demoted = []
          begin
            # STEP 2 — pivot the legacy mirror. D31: objid, because that is what
            # `bin/ots org doctor` compares against (Customer.load(owner_id) and
            # the objid-keyed members set). Tied to the deprecation note at
            # organization.rb:68 — if owner_id ever goes away, this step goes
            # with it, but `Organization#owner?` alone is not what the doctor
            # reads today.
            @org.owner_id = @new_owner.objid.to_s
            @org.save

            # STEP 3 — demote every other owner. sole_owner? is false now (step 1
            # created a second owner), so SetRole's guard passes. change_role!
            # re-materializes the demoted membership, so BOTH sides' entitlements
            # are correct with no extra work.
            outgoing.each do |membership|
              old_owner = membership.customer
              if old_owner.nil?
                # Stale member with no backing customer object — `org doctor`
                # check 3 territory. There is no Customer to hand SetRole, and
                # fabricating one is forbidden (ADR-023). Leave it for the doctor.
                OT.le "[Org::TransferOwnership] #{@org.extid} skipping owner membership with " \
                      'no backing customer object (run `bin/ots org doctor`)'
                next
              end

              set_role!(old_owner, @demote_to)
              demoted << old_owner.extid
            end
          rescue StandardError
            # Best-effort rollback BEFORE any audit is written — an aborted
            # transfer must never be recorded as a success. Already-demoted
            # memberships stay demoted (same partial-rollback posture as
            # Domains::Transfer); re-running the op converges.
            rollback!(original_owner_id, previous_target_role)
            raise
          end

          demoted
        end

        # @return [String, nil] the incoming owner's role before promotion, or
        #   nil when they were already an owner (nothing to roll back).
        def promote!(target)
          return nil if target.owner?

          result = set_role!(@new_owner, 'owner')
          result.from
        end

        def set_role!(customer, role)
          result = Onetime::Operations::Memberships::SetRole.new(
            org: @org,
            customer: customer,
            new_role: role,
            actor: @actor,
          ).call
          unless [:success, :no_change].include?(result.status)
            raise Onetime::Problem,
              "Failed to set role '#{role}' for #{customer.extid} in #{@org.extid}: #{result.status}"
          end

          result
        end

        def rollback!(original_owner_id, previous_target_role)
          @org.owner_id = original_owner_id
          @org.save
          set_role!(@new_owner, previous_target_role) if previous_target_role
        rescue StandardError => ex
          # Never mask the original failure with a rollback failure.
          OT.le "[Org::TransferOwnership] rollback failed for #{@org.extid}: #{ex.class}: #{ex.message}"
        end

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op. `dry_run` is carried so a refused preview is distinguishable
        # from a refused apply.
        def record_refusal(status)
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @org.extid,
            result: :failure,
            detail: {
              reason: status.to_s,
              from: @from_owner_id,
              to: @new_owner.extid,
              demoted_to: @demote_to,
              dry_run: @dry_run,
            },
          )
        rescue StandardError => ex
          OT.le "[Org::TransferOwnership] refusal audit failed: #{ex.class}: #{ex.message}"
        end

        # Single exit point for every non-applied status, so the refusal audit
        # cannot be forgotten at an early return.
        def build(status, demoted: [])
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            org_id: @org.extid,
            from_owner_id: @from_owner_id,
            from_owner_role_after: @demote_to,
            to_owner_id: @new_owner.extid,
            demoted: demoted,
            orphaned_owner: @orphaned_owner || false,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end
