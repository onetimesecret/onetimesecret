# lib/onetime/operations/email/ingest_feedback.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Deliverability feedback is mailer-wide
# infrastructure (like {Onetime::Operations::Email::SendTest}), so it lives in
# the central operations home. Loaded at the call site, so require the
# dependencies explicitly.
require 'onetime/models/email_suppression'
require 'onetime/models/admin_audit_event'

module Onetime
  module Operations
    module Email
      # Ingest a batch of ESP deliverability feedback (bounces / complaints /
      # suppression imports) into {Onetime::EmailSuppression} — the SINGLE,
      # audited implementation of the feedback-ingest verb.
      #
      # ## Intended flow (why this is an op, not a webhook)
      #
      # There is no public webhook receiver on purpose: an unauthenticated
      # bounce endpoint is a suppression-injection vector (anyone could silence
      # a victim's email). Instead, an operator-controlled relay (CLI/cron)
      # reads feedback from the ESP — SES SNS notifications, a SendGrid event
      # export, Lettermint bounce logs, an SMTP provider's report — normalizes
      # it to `{email, kind, reason?, source?}` records, and POSTs them through
      # the colonel-authenticated endpoint
      # (`POST /api/colonel/email/deliverability/events`), which adapts to this
      # op. See the endpoint class for the wire format.
      #
      # ## Record semantics
      #
      # - kind 'bounce' / 'complaint': recorded into the event feed AND the
      #   address is suppressed (reason = the kind). ESP-reported hard bounces
      #   and complaints are authoritative "stop mailing this address" signals.
      # - kind 'suppression': suppress only (reason 'manual'), no feed event —
      #   used to import an existing ESP suppression list or to manually block
      #   an address.
      #
      # Malformed records are counted + described, never fatal: a feedback
      # pipe must not lose 499 good records over 1 bad row.
      #
      # ## Audit rule (CONTRACT 4)
      #
      # One {Onetime::AdminAuditEvent} per batch that accepted at least one
      # record (verb `email.deliverability_ingest`) — per-address events would
      # flood the audit trail with what is effectively one operator action. A
      # batch that accepts nothing mutates nothing and records no audit event.
      class IngestFeedback
        # Audit verb recorded once per accepting batch.
        AUDIT_VERB = 'email.deliverability_ingest'

        # Upper bound per call — a feedback pipe should chunk, not firehose.
        MAX_BATCH = 500

        # Accepted record kinds (EVENT_KINDS plus the import-only 'suppression').
        KINDS = %w[bounce complaint suppression].freeze

        # Cap on per-record error descriptions carried back to the caller.
        MAX_ERRORS = 10

        # Same minimal shape check the send-test logic uses for recipients.
        EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/

        # @!attribute accepted [r] @return [Integer] records ingested
        # @!attribute rejected [r] @return [Integer] records refused
        # @!attribute errors [r] @return [Array<String>] first MAX_ERRORS reasons
        Result = Data.define(:accepted, :rejected, :errors)

        # @param records [Array<Hash>] feedback records; each needs 'email'
        #   (or 'address') and 'kind' (or 'type'), optionally 'reason'/'source'.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param default_source [String, nil] provenance applied to records
        #   that carry no 'source' of their own (e.g. 'ses', 'sendgrid').
        def initialize(records:, actor:, default_source: nil)
          @records        = Array(records)
          @actor          = actor
          @default_source = default_source
        end

        # @return [Result]
        def call
          accepted = 0
          rejected = 0
          errors   = []

          @records.first(MAX_BATCH).each_with_index do |record, idx|
            error = ingest_one(record)
            if error
              rejected += 1
              errors << "record #{idx + 1}: #{error}" if errors.size < MAX_ERRORS
            else
              accepted += 1
            end
          end

          # One audit event per batch that actually changed state (CONTRACT 4).
          if accepted.positive?
            Onetime::AdminAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: 'email_suppression',
              result: :success,
              detail: { accepted: accepted, rejected: rejected, source: @default_source.to_s },
            )
          end

          Result.new(accepted: accepted, rejected: rejected, errors: errors)
        end

        private

        # Ingest a single record. @return [String, nil] an error description,
        # or nil when the record was accepted.
        def ingest_one(record)
          return 'not an object' unless record.is_a?(Hash)

          address = field(record, 'email') || field(record, 'address')
          address = Onetime::EmailSuppression.normalize(address)
          return 'missing or invalid email' unless EMAIL_PATTERN.match?(address)

          kind = (field(record, 'kind') || field(record, 'type')).to_s.strip.downcase
          return "unknown kind '#{kind}'" unless KINDS.include?(kind)

          source = field(record, 'source') || @default_source

          if kind == 'suppression'
            Onetime::EmailSuppression.suppress!(address: address, reason: 'manual', source: source)
          else
            Onetime::EmailSuppression.record_event(
              address: address,
              kind: kind,
              reason: field(record, 'reason'),
              source: source,
            )
            Onetime::EmailSuppression.suppress!(address: address, reason: kind, source: source)
          end

          nil
        end

        # Records arrive as parsed JSON (string keys) from HTTP, but accept
        # symbol keys too for CLI callers.
        def field(record, name)
          value = record[name] || record[name.to_sym]
          value.nil? ? nil : value.to_s
        end
      end
    end
  end
end
