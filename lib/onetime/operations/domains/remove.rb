# lib/onetime/operations/domains/remove.rb
#
# frozen_string_literal: true

# Domain-owned (app-scoped) operation — mirrors Operations::Domains::Transfer.
# Loaded at the call site (colonel logic + CLI), so require deps explicitly.
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/audit_attempt'
require 'onetime/operations/domains/teardown'

module Onetime
  module Operations
    module Domains
      # Permanently delete a custom domain. This is the shared implementation
      # of the remove operation (#3731 P3), called by thin adapters in the
      # colonel endpoint (DELETE /api/colonel/domains/:extid) and
      # `bin/ots domains remove`.
      #
      # Like Transfer, this operation defaults to dry_run: true and returns a
      # Result Data object. The operation alone emits ColonelAuditEvent;
      # adapters must not emit duplicate events.
      #
      # ## Shared teardown
      #
      # The apply path delegates to Domains::Teardown, which the customer API
      # also uses. Teardown handles provider cleanup and record destruction
      # under the sender identity lease. This wrapper handles previews and
      # operator auditing.
      #
      # Teardown does not call org.remove_domain because CustomDomain#destroy!
      # already removes the domain's organization participation.
      #
      # ## Index entries
      #
      # CustomDomain#destroy! releases its display_domain_index and
      # ascii_display_domain_index entries itself, ownership-checked and under
      # the name as stored. Removing a drift-produced shadow record that shares
      # a hostname with the record the index names leaves that record's entries
      # in place, so this wrapper has nothing to repair.
      class Remove
        include Onetime::AuditedFailure
        include Onetime::AuditReason
        include Onetime::Operations::AuditAttempt

        AUDIT_VERB = 'domain.remove'

        # Raised by an apply, before any teardown, while another holder has
        # the domain's sender identity lock (MailerConfig.sender_identity_lock):
        # provisioning, a sender config delete, or another removal. The apply
        # holds that lock from the teardown through destroy!. A provision
        # that ran in between would register the identity again after the
        # teardown, and destroy! would then delete the only record of it.
        # audit_failures records the refused attempt like any other raise.
        class SenderIdentityBusy < StandardError; end

        # The deletion is irreversible, but the caller must still see lease
        # loss. Carry the removed result instead of suggesting a safe retry.
        class RemovalCommitted < Onetime::Operations::SenderIdentityLease::Lost
          attr_reader :result

          def initialize(result:, lease_error:)
            @result = result
            super("Domain removal committed for #{result.extid}, but #{lease_error.message}")
          end
        end

        # A destructive verb: a removal that blows up partway leaves the fleet in
        # an unknown state, so the attempt must be in the trail even though the
        # success-path record never runs. Records one `result: :failure` and
        # re-raises.
        #
        # `dry_run` is in the detail because it defaults to TRUE here and the
        # success event is applied-path-only — without it an operator could not
        # tell a blown-up preview from a blown-up removal.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @audit_extid || @domain&.extid },
          detail: -> { { dry_run: @dry_run }.merge(@removal_committed ? { removal_committed: true } : {}) },
          enabled: -> { !@removal_audited }

        # @!attribute status [r] Symbol — :planned (dry-run) | :removed (applied)
        # @!attribute sender_cleanup [r] Symbol, nil — nil on a dry run; after
        #   an apply, Teardown::Result#sender_cleanup (:kept, :deleted,
        #   :absent, :skipped, or :failed)
        Result = Data.define(
          :status,
          :domain_id,
          :extid,
          :display_domain,
          :org_id,
          :org_name,
          :dry_run,
          :sender_cleanup,
        )

        # The applied teardown's sender cleanup outcome
        # (Teardown::Result#sender_cleanup), set before the success audit
        # write, so a caller can still report it when that write raises.
        # nil until a teardown returns.
        attr_reader :sender_cleanup

        # @param domain [Onetime::CustomDomain] resolved target (caller ensures non-nil).
        # @param actor [String, #extid] acting principal's PUBLIC id (colonel extid
        #   or the 'cli' sentinel) — never an objid.
        # @param dry_run [Boolean] preview only when true (default).
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338),
        #   recorded in the audit detail of the removal AND of the preview that
        #   preceded it. Blank is treated as absent and both details keep their
        #   pre-#4338 shape; see {Onetime::AuditReason} for the bound and the
        #   optional-now / required-later rollout.
        # @param keep_vhost [Boolean] leave the provider vhost in place
        #   (Teardown#initialize): for a record that shares its name with a
        #   record that stays. Recorded in the audit detail as vhost_kept.
        # @param keep_sender_identity [Boolean] preserve a keeper's shared remote
        #   sender identity, while still deleting this record and its local config.
        def initialize(domain:, actor:, dry_run: true, reason: nil, keep_vhost: false, keep_sender_identity: false)
          @domain               = domain
          @actor                = actor
          @dry_run              = dry_run
          @reason               = normalize_reason(reason)
          @keep_vhost           = keep_vhost
          @keep_sender_identity = keep_sender_identity
        end

        # @return [Result]
        def call
          @removal_committed = false
          @removal_audited   = false
          @audit_extid       = @domain.extid
          org_id             = @domain.org_id
          org                = org_id.to_s.empty? ? nil : Onetime::Organization.load(org_id)

          # Build the full Result NOW, before destroy! nils the domain's fields.
          plan = Result.new(
            status: :planned,
            domain_id: @domain.domainid,
            extid: @domain.extid,
            display_domain: @domain.display_domain,
            org_id: org_id,
            org_name: org&.display_name,
            dry_run: @dry_run,
            sender_cleanup: nil,
          )

          # --- DRY RUN: preview only, mutate nothing ---
          # Nothing reaches the OPERATOR trail, but a preview of a destructive
          # verb is reconnaissance — it names the domain and its org. Recorded
          # as an OBSERVATION (#4337).
          if @dry_run
            record_preview_event(org_id)
            return plan
          end

          # A returned teardown result is committed, even when its final lease
          # check failed. Complete the auditing before reporting loss.
          teardown           = teardown_domain
          @removal_committed = teardown.removal_committed
          @sender_cleanup    = teardown.sender_cleanup
          lease_error        = teardown.lease_error

          # --- EXACTLY ONE audit event, applied path only ---
          #
          # FAIL-CLOSED (#4333): a close peer of the named destructive verbs —
          # destroy! has committed and the vhost is gone, so an unrecorded
          # removal is indistinguishable from a domain that was never added.
          # The dry-run path returns above, recording only a preview
          # observation on the access trail (#4337), never this operator event.
          #
          # sender_cleanup records the remote sender identity outcome
          # (Teardown::Result#sender_cleanup), so the trail shows a failed
          # provider deletion.
          detail           = { org_id: org_id.to_s }
          detail           = detail.merge(vhost_kept: true) if @keep_vhost
          detail           = detail.merge(sender_identity_kept: true) if @keep_sender_identity
          detail           = detail.merge(sender_cleanup: teardown.sender_cleanup.to_s)
          if lease_error
            detail[:removal_committed] = true
            detail[:lease_lost]        = true
          end
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: plan.extid,
            result: :success,
            detail: with_reason(detail),
            fail_closed: true,
          )
          @removal_audited = true

          removed = plan.with(status: :removed, sender_cleanup: teardown.sender_cleanup)
          if lease_error
            raise RemovalCommitted.new(result: removed, lease_error: lease_error), cause: lease_error
          end

          removed
        end

        private

        # The #4337 envelope's target hook: the domain's public id, read the
        # same lazy way the failure audit above reads it. Identical to the
        # `plan.extid` this emitter used to pass — the plan copies it from
        # @domain, and the dry-run path returns before the destroy. The plan
        # itself is still threaded in so the emitter's signature stays parallel
        # to the applied-event call site's.
        def audit_target = @domain.extid

        # One OBSERVATION per preview (#4337), on the budgeted access trail —
        # never the operator trail, which stays a record of domains that were
        # actually removed. Same verb and target as the applied event so a
        # preview lines up with the removal that followed it; `result: 'preview'`
        # is what tells them apart, and the detail mirrors the applied event's —
        # including the operator's `reason` (#4338) when one was given.
        def record_preview_event(org_id)
          detail = { org_id: org_id.to_s }
          detail = detail.merge(vhost_kept: true) if @keep_vhost
          detail = detail.merge(sender_identity_kept: true) if @keep_sender_identity
          record_preview_observation(with_reason(detail))
        end

        def teardown_domain
          Onetime::Operations::Domains::Teardown.new(
            domain: @domain,
            keep_vhost: @keep_vhost,
            keep_sender_identity: @keep_sender_identity,
          ).call
        rescue Onetime::Operations::Domains::Teardown::Busy => ex
          # Preserve the toolbox exception contract and failure-audit class.
          raise SenderIdentityBusy, ex.message
        end
      end
    end
  end
end
