# lib/onetime/operations/org/unarchive.rb
#
# frozen_string_literal: true

# Loaded at the call site (CLI today), which runs outside the app autoloaders —
# require the audit model explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/operations/audit_attempt'

module Onetime
  module Operations
    module Org
      # Reverse a soft-archive on an organization — the SINGLE implementation of
      # the unarchive verb, and the repair tool for #4717.
      #
      # Adapters:
      #   - `bin/ots org unarchive ORG [--run]`
      #
      # ## Why this exists
      #
      # The tenant SSO self-heal (JoinDomainOrganization#adopt_domain_default_org)
      # archived the organization the customer was joining whenever the signed-in
      # customer owned the domain org and it carried `is_default: true`. It was
      # archived on the owner's tenant SSO login, and again on the first login
      # after any restore until the guard is live (the self-heal skips an org
      # that is already archived), with the self-referential comment
      # "Superseded by domain org <its own extid> via SSO self-heal". The
      # guard that stops that is in the same PR; this op restores the records it
      # left behind. `Organization#unarchive!` is the only primitive that resets
      # `archived_at` AND `archived_comment` together, and this op is its only
      # caller.
      #
      # ## Statuses
      #
      #   :not_archived  nothing to do; no write, no audit event (plan or apply).
      #   :planned       dry run; no write, one preview observation (#4337).
      #   :success       `unarchive!` ran; one operator-trail event.
      #
      # There is no refusal path. `pointer_org_id` is ADVISORY: the self-heal
      # archives only the workspace the owner's default pointer resolves to
      # (explicit `default_org_id`, else the owned `is_default` workspace), so a
      # pointer at a different live org leaves this one untouched after the
      # unarchive. The pointer is reported so the operator can see the owner
      # will not land here; nothing refuses on it.
      #
      # ## Audit (CONTRACT 4)
      #
      # Exactly ONE {Onetime::ColonelAuditEvent} ({AUDIT_VERB}) per applied
      # unarchive, carrying the comment that was cleared so the trail keeps the
      # reason the org was archived, and the advisory pointer (nil when none).
      # A dry run records an OBSERVATION on the access trail (#4337), never an
      # operator-trail event. `:not_archived` records nothing: it is a read that
      # found nothing to move. Adapters MUST NOT audit.
      #
      # ## Deliberate omissions
      #
      # - `default_org_id` is NOT repointed. Which org the owner should default
      #   to is a human decision; the pointer is reported (`pointer_org_id`) so
      #   the operator can make it.
      # - Nothing else on the org moves: `is_default`, plan, Stripe fields and
      #   memberships were never touched by the archive and are not touched here.
      #
      # ## Constant-lookup discipline
      #
      # Always fully qualify `Onetime::Organization` / `Onetime::Customer` here
      # (precedent: transfer_ownership.rb); the specs stub them by that name.
      class Unarchive
        include Onetime::AuditedFailure
        include Onetime::Operations::AuditAttempt

        # Full-noun subject, matching the rest of the admin trail
        # (`organization.create`, `organization.transfer_ownership`).
        AUDIT_VERB = 'organization.unarchive'

        # Statuses the adapters treat as "not a failure" — which is every
        # status this op returns. There is no refusal path.
        OK_STATUSES = [:planned, :success, :not_archived].freeze

        # The success record sits after `unarchive!`, so a raise anywhere in the
        # applied path would otherwise leave no trace. Records one
        # `result: :failure` and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @org&.extid },
          detail: -> { { dry_run: @dry_run } }

        # @!attribute status [r] Symbol — :planned (dry run) | :success | :not_archived
        # @!attribute org_id [r] String — the org's PUBLIC extid.
        # @!attribute display_name [r] String
        # @!attribute owner_id [r] String, nil — PUBLIC extid of the customer
        #   `org.owner_id` names, or nil when blank or resolving to no live
        #   customer (`org doctor` check 1). Never an objid.
        # @!attribute pointer_org_id [r] String, nil — ADVISORY. PUBLIC extid of
        #   the org the owner's `default_org_id` names when that is a DIFFERENT,
        #   LIVE org; nil when the pointer is empty, names this org, or names an
        #   archived or missing org. Never changes the status.
        # @!attribute archived_comment [r] String, nil — `org.archived_comment`
        #   at call time (the reason being cleared), echoed on every status.
        # @!attribute dry_run [r] Boolean
        Result = Data.define(
          :status,
          :org_id,
          :display_name,
          :owner_id,
          :pointer_org_id,
          :archived_comment,
          :dry_run,
        )

        # @param org [Onetime::Organization] resolved org (the adapter resolves).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param dry_run [Boolean] preview only when true (THE DEFAULT — same
        #   posture as TransferOwnership and Delete).
        def initialize(org:, actor:, dry_run: true)
          @org     = org
          @actor   = actor
          @dry_run = dry_run
        end

        # @return [Result]
        def call
          # Snapshot before anything moves: `unarchive!` clears the comment.
          # Owner and pointer are read-only lookups and every status, including
          # :not_archived, reports them (the Result contract), so they are
          # resolved before the early return.
          @archived_comment = @org.archived_comment
          resolve_owner_pointer!

          unless @org.archived?
            OT.info "[Org::Unarchive] #{@org.extid} is not archived; nothing to do (dry_run=#{@dry_run})"
            return build(:not_archived)
          end

          if @dry_run
            record_preview_event
            return build(:planned)
          end

          # The one primitive that resets archived_at AND archived_comment
          # together. No direct field writes here.
          @org.unarchive!

          # Exactly one audit event per applied unarchive, emitted here. PUBLIC
          # ids only — never objid/custid. `pointer_org_id` is present even when
          # nil so the event always answers "where did the owner default to".
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @org.extid,
            result: :success,
            detail: {
              archived_comment: @archived_comment,
              pointer_org_id: @pointer_org_id,
            },
          )

          OT.info "[Org::Unarchive] #{@org.extid} unarchived by #{@actor} " \
                  "pointer_org_id=#{@pointer_org_id || '(none)'} comment=#{@archived_comment.to_s.inspect}"

          build(:success)
        end

        private

        # Resolve the owner (for the Result) and the org their `default_org_id`
        # names, when that is a different live org. Both are reads; a datastore
        # failure here propagates (and is audited by `audit_failures`) rather
        # than being swallowed into a report that then cannot be trusted.
        def resolve_owner_pointer!
          owner_id        = @org.owner_id.to_s
          owner           = owner_id.empty? ? nil : Onetime::Customer.load(owner_id)
          @owner_id       = owner&.extid
          @pointer_org_id = nil
          return unless owner

          pointer = owner.default_org_id.to_s
          return if pointer.empty? || pointer == @org.objid.to_s

          target = Onetime::Organization.load(pointer)
          return if target.nil? || target.archived?

          @pointer_org_id = target.extid
        end

        # One OBSERVATION per preview (#4337), on the budgeted access trail.
        # Same verb and target as the applied event so a preview and the
        # unarchive that followed read as one sequence.
        def record_preview_event
          record_preview_observation(
            owner_id: @owner_id,
            pointer_org_id: @pointer_org_id,
            archived_comment: @archived_comment,
          )
        end

        # The #4337 envelope's target hook: the org's public id, same as the
        # applied event's.
        def audit_target = @org.extid

        # Single exit point for every status, so every Result carries the same
        # snapshot.
        def build(status)
          Result.new(
            status: status,
            org_id: @org.extid,
            display_name: @org.display_name,
            owner_id: @owner_id,
            pointer_org_id: @pointer_org_id,
            archived_comment: @archived_comment,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end
