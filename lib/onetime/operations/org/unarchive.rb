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
      #   - `bin/ots org unarchive ORG [--run] [--force]`
      #
      # ## Why this exists
      #
      # The tenant SSO self-heal (JoinDomainOrganization#adopt_domain_default_org)
      # archived the organization the customer was joining whenever the signed-in
      # customer owned the domain org and it carried `is_default: true`. Every
      # tenant SSO login of the owner re-archived it, with the self-referential
      # comment "Superseded by domain org <its own extid> via SSO self-heal". The
      # guard that stops that is in the same PR; this op restores the records it
      # left behind. `Organization#unarchive!` is the only primitive that resets
      # `archived_at` AND `archived_comment` together, and this op is its only
      # caller.
      #
      # ## Guardrails — statuses, not raises
      #
      # Every non-applied outcome RETURNS a {Result} whose `status` names it.
      # Evaluated in this order, first trip wins:
      #
      #   :not_archived              nothing to do; no write, no audit event.
      #   :default_pointer_elsewhere the owner's `default_org_id` names a
      #                              DIFFERENT, LIVE organization. Refused by
      #                              default (override with `force: true`).
      #
      # The pointer refusal is temporary by design: the #4717 plan drops it to
      # an advisory field once PR 2 removes the archive call from
      # JoinDomainOrganization. Until then the login self-heal still archives
      # the `is_default` workspace the owner resolves to (explicit pointer
      # first, else the owned default) when it is not the domain org being
      # joined. A pointer at another live org means the owner has moved on from
      # this workspace: restoring it changes nothing about where they land, and
      # the operator should decide deliberately whether to repoint the default.
      # Refusing surfaces that on the plan pass; `force: true` is for the
      # operator who has made that decision. A pointer that is empty, names
      # this org, or names an archived or missing org is not "elsewhere".
      #
      # Note that the pointer-elsewhere state is NOT what re-archives a restored
      # workspace. With the pointer at another existing org, the self-heal's
      # explicit path returns that org and this one is never the candidate. The
      # state the self-heal does re-archive is the opposite one — the pointer
      # names this workspace (or is empty and this is the owned default) and
      # the owner signs in to a DIFFERENT domain org. That is the legitimate
      # adoption case, and no guard here prevents it.
      #
      # ## Audit (CONTRACT 4)
      #
      # Exactly ONE {Onetime::ColonelAuditEvent} ({AUDIT_VERB}) per applied
      # unarchive, carrying the comment that was cleared so the trail keeps the
      # reason the org was archived. A refusal records one `result: :failure`
      # (an attempted privileged mutation, same posture as TransferOwnership).
      # A dry run records an OBSERVATION on the access trail (#4337), never an
      # operator-trail event. `:not_archived` records nothing: it is a read that
      # found nothing to move, on both the plan and the applied pass. Adapters
      # MUST NOT audit.
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

        # Statuses the adapters treat as "not a failure".
        OK_STATUSES = [:planned, :success, :not_archived].freeze

        # The complement: a privileged mutation was asked for and REFUSED. Each
        # records one `result: :failure` event.
        REFUSAL_STATUSES = [:default_pointer_elsewhere].freeze

        # The success record sits after `unarchive!`, so a raise anywhere in the
        # applied path would otherwise leave no trace. Records one
        # `result: :failure` and re-raises.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @org&.extid },
          detail: -> { { dry_run: @dry_run, force: @force } }

        # @!attribute status [r] Symbol —
        #   :planned (dry run) | :success | :not_archived | :default_pointer_elsewhere
        # @!attribute org_id [r] String — the org's PUBLIC extid.
        # @!attribute display_name [r] String
        # @!attribute owner_id [r] String, nil — PUBLIC extid of the customer
        #   `org.owner_id` names, or nil when blank or resolving to no live
        #   customer (`org doctor` check 1). Never an objid.
        # @!attribute pointer_org_id [r] String, nil — PUBLIC extid of the org
        #   the owner's `default_org_id` names when that is a DIFFERENT, LIVE
        #   org; nil when the pointer is empty, names this org, or names an
        #   archived or missing org. Reported on every status, forced or not.
        # @!attribute archived_comment [r] String, nil — `org.archived_comment`
        #   at call time (the reason being cleared), echoed on every status.
        # @!attribute force [r] Boolean — the override as passed.
        # @!attribute dry_run [r] Boolean
        Result = Data.define(
          :status,
          :org_id,
          :display_name,
          :owner_id,
          :pointer_org_id,
          :archived_comment,
          :force,
          :dry_run,
        )

        # @param org [Onetime::Organization] resolved org (the adapter resolves).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid, or the CLI sentinel). Never an internal objid.
        # @param dry_run [Boolean] preview only when true (THE DEFAULT — same
        #   posture as TransferOwnership and Delete).
        # @param force [Boolean] unarchive even when the owner's default pointer
        #   names another live org (see the class docs for the consequence).
        def initialize(org:, actor:, dry_run: true, force: false)
          @org     = org
          @actor   = actor
          @dry_run = dry_run
          @force   = force
        end

        # @return [Result]
        def call
          # Snapshot before anything moves: `unarchive!` clears the comment.
          @archived_comment = @org.archived_comment

          unless @org.archived?
            OT.info "[Org::Unarchive] #{@org.extid} is not archived; nothing to do (dry_run=#{@dry_run})"
            return build(:not_archived)
          end

          resolve_owner_pointer!
          return build(:default_pointer_elsewhere) if @pointer_org_id && !@force

          if @dry_run
            record_preview_event
            return build(:planned)
          end

          # The one primitive that resets archived_at AND archived_comment
          # together. No direct field writes here.
          @org.unarchive!

          # Exactly one audit event per applied unarchive, emitted here. PUBLIC
          # ids only — never objid/custid.
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @org.extid,
            result: :success,
            detail: {
              archived_comment: @archived_comment,
              forced: @force,
              pointer_org_id: @pointer_org_id,
            }.compact,
          )

          OT.info "[Org::Unarchive] #{@org.extid} unarchived by #{@actor} forced=#{@force} " \
                  "pointer_org_id=#{@pointer_org_id || '(none)'} comment=#{@archived_comment.to_s.inspect}"

          build(:success)
        end

        private

        # Resolve the owner (for the Result) and the org their `default_org_id`
        # names, when that is a different live org. Both are reads; a datastore
        # failure here propagates (and is audited by `audit_failures`) rather
        # than being swallowed into a guard that then cannot be trusted.
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

        # Same verb/target/actor as the success event. Best-effort: never break
        # the op. `dry_run` is carried so a refused preview is distinguishable
        # from a refused apply.
        def record_refusal(status)
          OT.info "[Org::Unarchive] refused #{@org.extid}: #{status} pointer_org_id=#{@pointer_org_id} " \
                  "dry_run=#{@dry_run}"
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @org.extid,
            result: :failure,
            detail: {
              reason: status.to_s,
              owner_id: @owner_id,
              pointer_org_id: @pointer_org_id,
              archived_comment: @archived_comment,
              dry_run: @dry_run,
            },
          )
        rescue StandardError => ex
          OT.le "[Org::Unarchive] refusal audit failed: #{ex.class}: #{ex.message}"
        end

        # One OBSERVATION per preview (#4337), on the budgeted access trail.
        # Same verb and target as the applied event so a preview and the
        # unarchive that followed read as one sequence.
        def record_preview_event
          record_preview_observation(
            owner_id: @owner_id,
            pointer_org_id: @pointer_org_id,
            archived_comment: @archived_comment,
            force: @force,
          )
        end

        # The #4337 envelope's target hook: the org's public id, same as the
        # applied event's.
        def audit_target = @org.extid

        # Single exit point for every status, so the refusal audit cannot be
        # forgotten at an early return and every Result carries the same
        # snapshot.
        def build(status)
          record_refusal(status) if REFUSAL_STATUSES.include?(status)

          Result.new(
            status: status,
            org_id: @org.extid,
            display_name: @org.display_name,
            owner_id: @owner_id,
            pointer_org_id: @pointer_org_id,
            archived_comment: @archived_comment,
            force: @force,
            dry_run: @dry_run,
          )
        end
      end
    end
  end
end
