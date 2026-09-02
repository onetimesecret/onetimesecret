# apps/api/colonel/logic/colonel/delete_secret.rb
#
# frozen_string_literal: true

require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Destroy a secret and its receipt (DELETE /api/colonel/secrets/:secret_id).
      #
      # ## Audited inline, not via an op
      #
      # This is the only destructive colonel route that mutates directly in
      # `#process` — purge, domain remove, session delete and DLQ purge all
      # delegate to an Operations class that owns its own audit event. Extracting
      # an `Operations::Secrets::Delete` is the right long-term shape but is not
      # this change; until then the audit event is written here, using the same
      # actor/target/detail contract every op follows.
      #
      # ## Identifiers
      #
      # `target` and `detail` carry PUBLIC ids only (shortid). `secret.objid` and
      # `owner_id` are internal and must never reach the audit trail — they stay
      # confined to the response body, which is an authenticated colonel-only
      # payload with its own long-standing shape.
      class DeleteSecret < ColonelAPI::Logic::Base
        include Onetime::AuditedFailure

        AUDIT_VERB = 'secret.delete'

        # Failure auditing (Onetime::AuditedFailure). Wraps #process, which Otto
        # runs AFTER #raise_concerns — so the colonel-role check and the
        # not-found lookup that live there are structurally outside the audited
        # region, and an authorization rejection can never write an event.
        # A destroy! that blows up mid-teardown (receipt gone, secret left) does.
        # `actor` is explicit here: the ops' `@actor` default does not exist on a
        # Logic class — the acting colonel is `cust` (PUBLIC id, never an objid).
        audit_failures :process,
          verb: AUDIT_VERB,
          target: -> { @audit_target },
          actor: -> { cust&.extid }

        attr_reader :secret_id, :secret, :receipt, :deleted_secret, :deleted_receipt

        # `reason` (#4338) is OPTIONAL and rides the QUERY STRING, because this
        # is a DELETE and request bodies are not reliably parsed across this
        # stack (the same reason DeleteOrganization / RemoveCustomDomain read
        # their flags from the query). This route audits INLINE rather than
        # through an op, so `@reason` feeds {#with_reason} in #process directly
        # instead of an op kwarg.
        def process_params
          @secret_id = sanitize_identifier(params['secret_id'])
          @reason    = operator_reason_param
          raise_form_error('Secret ID is required', field: :secret_id) if secret_id.to_s.empty?
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)

          @secret = Onetime::Secret.load(secret_id)
          raise_not_found('Secret not found') unless secret&.exists?

          # Public id + state captured BEFORE the destroy, for the audit record.
          # Reading them off a destroyed record is not something to rely on, and
          # the failure wrapper needs a target even when destroy! raises.
          @audit_target = secret.shortid
          @audit_state  = secret.state.to_s

          # Load associated receipt (also the source of the confirmation token
          # below).
          if secret.receipt_identifier
            @receipt = Onetime::Receipt.load(secret.receipt_identifier)
          end

          # TIER 1 (#4326). The confirmation token is the RECEIPT shortid — an
          # identifier the URL does NOT carry. The route is keyed by :secret_id
          # (the secret objid), and secret.shortid is just secret_id[0,8], so
          # confirming with it would be no second factor at all: a scraped-URL
          # replay derives it for free. The receipt has its own objid, so its
          # shortid is independent of :secret_id and forces the replay to know a
          # second identifier (design §1.1). `@audit_target` stays secret.shortid
          # for the audit record only — the two are deliberately not conflated.
          # LAZY token (a lambda, not confirmation_token itself): its receiptless
          # fail-closed raise must run AFTER require_elevation!, or an unelevated
          # caller gets a 500 GuardMisconfigured where the guard-order contract
          # promises 403 ElevationRequired first (no confirmation oracle).
          guard_destructive_action!(
            tier: :destructive,
            confirm_with: -> { confirmation_token },
            confirm_subject: 'the receipt shortid',
            field: :secret_id,
          )
          charge_destructive_budget!
        end

        # The confirmation token for this destroy: the RECEIPT shortid (#4326).
        # Independent of :secret_id by construction — the receipt has its own
        # objid, so its shortid is not derivable from the URL. Prefer the stored
        # `receipt_shortid` field; fall back to the loaded receipt's shortid
        # (the field is not populated on legacy pairs, but the receipt is).
        #
        # FAIL-CLOSED when neither yields a shortid: a secret with no resolvable
        # receipt has no non-URL identifier to confirm against. Rather than fall
        # back to the URL-derivable secret shortid — which would silently defeat
        # #4326 — we refuse (GuardMisconfigured, 500) and the operator removes it
        # with the CLI. Preferring refusal over a weak token is the safe
        # direction for a TIER 1 destroy; over-refusing a receiptless secret is
        # acceptable, admitting a replayable one is not.
        def confirmation_token
          token = secret.receipt_shortid.to_s.strip
          token = receipt.shortid.to_s if token.empty? && receipt&.exists?
          return token unless token.empty?

          OT.le "[DeleteSecret] no receipt shortid for secret #{@audit_target}; refusing confirmation (#4326)"
          raise Onetime::GuardMisconfigured,
            'Cannot confirm secret deletion: this secret has no receipt to derive an ' \
            'independent confirmation token from. Remove it with the CLI instead.'
        end

        def process
          # Delete receipt first (if exists)
          if receipt&.exists?
            @deleted_receipt = {
              receipt_id: receipt.objid,
              shortid: receipt.shortid,
            }
            receipt.destroy!
          end

          # Delete secret
          @deleted_secret = {
            secret_id: secret.objid,
            shortid: secret.shortid,
            state: secret.state,
            owner_id: secret.owner_id,
          }
          secret.destroy!

          # One audit event per successful destroy. Built independently of
          # @deleted_secret: that hash carries internal ids for the response
          # body, and internal ids must not enter the audit trail. Never any
          # secret content — state and shortid only.
          #
          # FAIL-CLOSED (#4333): the secret and its receipt are destroyed, so
          # an operator deleting someone's secret leaves no other trace. An
          # unwritable event raises Onetime::AuditWriteFailure, which surfaces
          # as a 500 rather than a 200 for an unrecorded destroy.
          Onetime::ColonelAuditEvent.record(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: @audit_target,
            result: :success,
            detail: with_reason(
              state: @audit_state,
              receipt_shortid: deleted_receipt&.fetch(:shortid, nil),
            ),
            fail_closed: true,
          )

          success_data
        end

        def success_data
          {
            record: {
              deleted: true,
              secret: deleted_secret,
              metadata: deleted_receipt, # maintain public API
            },
            details: {
              message: 'Secret and associated receipt deleted successfully',
            },
          }
        end
      end
    end
  end
end
