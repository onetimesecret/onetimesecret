# lib/onetime/operations/email/add_suppression.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Sibling of
# {Onetime::Operations::Email::RemoveSuppression}; loaded at the call site, so
# require the dependencies explicitly.
require 'onetime/models/email_suppression'
require 'onetime/models/admin_audit_event'

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
      # records EXACTLY ONE {Onetime::AdminAuditEvent} (verb `email.suppress`)
      # ONLY on a real state change (status non-nil). A blank address returns nil
      # (no mutation) and records NO audit event — "only audit an actual change".
      class AddSuppression
        # Audit verb recorded for every actual suppression add/refresh.
        AUDIT_VERB = 'email.suppress'

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

          # Only audit an actual state change. A blank address → suppress! nil →
          # no mutation → no audit event.
          if status
            Onetime::AdminAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: normalized,
              result: :success,
              detail: { reason: @reason, source: @source, change: status.to_s },
            )
          end

          Result.new(status: status, address: normalized)
        end
      end
    end
  end
end
