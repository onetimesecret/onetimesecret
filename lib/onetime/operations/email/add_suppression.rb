# lib/onetime/operations/email/add_suppression.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Sibling of
# {Onetime::Operations::Email::RemoveSuppression}; loaded at the call site, so
# require the dependencies explicitly.
require 'onetime/models/email_suppression'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    module Email
      # Manually add one address to the email suppression list — the SINGLE,
      # audited implementation of the manual-suppress verb (the mirror of
      # {Onetime::Operations::Email::RemoveSuppression}).
      #
      # The HTTP adapter (`POST /api/colonel/email/deliverability/suppressions`)
      # passes ONLY the address; `reason` is always 'manual' and `source' is the
      # caller-supplied provenance ('colonel' from the HTTP path). A
      # client-supplied reason would mislabel the entry, so it is fixed here.
      #
      # ## Audit rule (CONTRACT 4)
      #
      # {EmailSuppression.suppress!} returns :created | :updated | nil. This op
      # records EXACTLY ONE {Onetime::ColonelAuditEvent} (verb `email.suppress`)
      # ONLY on a real state change (status non-nil). A blank address mutates
      # nothing and records one `result: :failure` instead: it is a REFUSED
      # attempt (the colonel adapter renders it as a form error, "Address is
      # required"), not an idempotent no-op.
      class AddSuppression
        include Onetime::AuditedFailure

        # Audit verb recorded for every actual suppression add/refresh.
        AUDIT_VERB = 'email.suppress'

        # `suppress!` writes the record and its index before the success record
        # runs. Records one `result: :failure` and re-raises. The target is the
        # raw input here — `normalize` is a local on the success path and cannot
        # be assumed to have run.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @address },
          detail: -> { { reason: @reason, source: @source } }

        # @!attribute status [r]
        #   @return [Symbol, nil] :created, :updated, or nil (blank address)
        # @!attribute address [r]
        #   @return [String] the normalized address
        Result = Data.define(:status, :address)

        # @param address [String] recipient address (normalized in suppress!).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        # @param reason [String] suppression reason (default 'manual').
        # @param source [String] provenance, e.g. 'colonel' (default 'manual').
        def initialize(address:, actor:, reason: 'manual', source: 'manual')
          @address = address
          @actor   = actor
          @reason  = reason
          @source  = source
        end

        # @return [Result]
        def call
          status     = Onetime::EmailSuppression.suppress!(
            address: @address,
            reason: @reason,
            source: @source,
          )
          normalized = Onetime::EmailSuppression.normalize(@address)

          if status
            Onetime::ColonelAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: normalized,
              result: :success,
              detail: { reason: @reason, source: @source, change: status.to_s },
            )
          else
            # suppress! returns nil ONLY for a blank address: nothing was
            # written, and the operator's request was refused.
            record_refusal(:blank_address)
          end

          Result.new(status: status, address: normalized)
        end

        private

        # Same verb/actor as the success event. Best-effort: never break the op.
        def record_refusal(reason)
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @address.to_s,
            result: :failure,
            detail: { reason: reason.to_s, source: @source },
          )
        rescue StandardError => ex
          OT.le "[Email::AddSuppression] refusal audit failed: #{ex.class}: #{ex.message}"
        end
      end
    end
  end
end
