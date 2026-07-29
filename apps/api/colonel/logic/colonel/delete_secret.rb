# apps/api/colonel/logic/colonel/delete_secret.rb
#
# frozen_string_literal: true

require 'onetime/models/admin_audit_event'
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

        def process_params
          @secret_id = sanitize_identifier(params['secret_id'])
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

          # Load associated receipt
          if secret.receipt_identifier
            @receipt = Onetime::Receipt.load(secret.receipt_identifier)
          end
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
          Onetime::AdminAuditEvent.record(
            actor: cust&.extid,
            verb: AUDIT_VERB,
            target: @audit_target,
            result: :success,
            detail: {
              state: @audit_state,
              receipt_shortid: deleted_receipt&.fetch(:shortid, nil),
            },
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
