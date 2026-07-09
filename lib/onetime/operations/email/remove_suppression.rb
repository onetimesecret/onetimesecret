# lib/onetime/operations/email/remove_suppression.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Sibling of
# {Onetime::Operations::Email::IngestFeedback}; loaded at the call site, so
# require the dependencies explicitly.
require 'onetime/models/email_suppression'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Email
      # Remove one address from the email suppression list — the SINGLE,
      # audited implementation of the suppression-remove verb (the
      # {Onetime::Operations::UnbanIP} pattern for the deliverability lane).
      #
      # Removing a suppression re-enables outbound mail to an address that
      # previously bounced or complained, so the HTTP adapter
      # (`DELETE /api/colonel/email/deliverability/suppressions/:address`)
      # gates it behind a confirm dialog; the op itself just performs + audits.
      #
      # Stateless, single `#call`, returns an immutable {Result}. Removing an
      # address that is not suppressed returns `status: :not_found` and records
      # NO audit event (nothing mutated) — the "only audit an actual change"
      # rule (CONTRACT 4).
      class RemoveSuppression
        # Audit verb recorded for every successful removal.
        AUDIT_VERB = 'email.suppression_remove'

        # @!attribute status [r]
        #   @return [Symbol] :removed (entry deleted) or :not_found (no-op)
        # @!attribute entry [r]
        #   @return [Hash, nil] the entry as it was before removal
        Result = Data.define(:status, :address, :entry)

        # @param address [String] the suppressed address (normalized here).
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        def initialize(address:, actor:)
          @address = Onetime::EmailSuppression.normalize(address)
          @actor   = actor
        end

        # @return [Result]
        def call
          entry   = Onetime::EmailSuppression.lookup(@address)
          removed = Onetime::EmailSuppression.remove!(@address)

          unless removed
            return Result.new(status: :not_found, address: @address, entry: nil)
          end

          # One audit event per successful mutation. The address is the public
          # target (the SendTest precedent); detail keeps why it was suppressed
          # so the trail explains what protection was lifted.
          Onetime::AdminAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @address,
            result: :success,
            detail: entry ? { reason: entry['reason'], source: entry['source'] } : nil,
          )

          Result.new(status: :removed, address: @address, entry: entry)
        end
      end
    end
  end
end
