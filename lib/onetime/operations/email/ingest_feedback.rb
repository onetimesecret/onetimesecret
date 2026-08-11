# lib/onetime/operations/email/ingest_feedback.rb
#
# frozen_string_literal: true

# Central (cross-cutting) admin operation — see decision D3 in
# lib/onetime/operations/README.md. Deliverability feedback is mailer-wide
# infrastructure (like {Onetime::Operations::Email::SendTest}), so it lives in
# the central operations home. Loaded at the call site, so require the
# dependencies explicitly.
require 'onetime/models/email_suppression'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

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
      # - kind 'suppression': suppress only, no feed event — used to import an
      #   existing ESP suppression list (the SyncProviderFeedback pull path) or
      #   to manually block an address. The record's `reason`, when it is a valid
      #   suppression reason (bounce | complaint | manual), is preserved so an
      #   imported SES/Lettermint list keeps its bounce-vs-complaint breakdown;
      #   anything else (or absent) falls back to 'manual'. No feed event is
      #   written, so a periodic re-sync of the provider list is idempotent and
      #   never floods the bounce/complaint feed.
      #
      # Malformed records are counted + described, never fatal: a feedback
      # pipe must not lose 499 good records over 1 bad row.
      #
      # ## Audit rule (CONTRACT 4)
      #
      # One {Onetime::ColonelAuditEvent} per batch that accepted at least one
      # record (verb `email.deliverability_ingest`) — per-address events would
      # flood the audit trail with what is effectively one operator action. A
      # batch that accepts nothing mutates nothing and records no audit event.
      class IngestFeedback
        include Onetime::AuditedFailure

        # Audit verb recorded once per accepting batch.
        AUDIT_VERB = 'email.deliverability_ingest'

        # This op has NO refusal STATUS — per-record failures are COUNTED
        # (`rejected` + `errors`), not raised, so a batch that accepts nothing
        # is an honest outcome rather than a refusal. What raises is a failure
        # of the ingest machinery itself, part-way through a loop that has
        # already suppressed some addresses, with the batch's single success
        # record still ahead of it. Records one `result: :failure` and re-raises.
        #
        # The target mirrors the success event's fixed 'email_suppression'
        # sentinel: the batch has no single public id, and the addresses are the
        # data, not the target.
        #
        # NON-OPERATOR DRIVER, checked: {SyncProviderFeedback} feeds this op
        # in-process from `bin/ots email sync-feedback` on a cron. That does NOT
        # make the failure event a mislabel of scheduled work as operator
        # activity (the {Onetime::Operations::AdminVerifyDomain} concern),
        # because the SUCCESS event already travels that same path under the
        # same `SyncProviderFeedback::CLI_ACTOR` sentinel — the failure is
        # symmetric with it. Volume is bounded the same way too: ONE event per
        # run, not per record, since per-record failures are counted rather than
        # raised.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: 'email_suppression',
          detail: -> { { source: @default_source.to_s, batch_size: @records.size } }

        # Upper bound per call — a feedback pipe should chunk, not firehose.
        MAX_BATCH = 500

        # Accepted record kinds (EVENT_KINDS plus the import-only 'suppression').
        KINDS = %w[bounce complaint suppression].freeze

        # Cap on per-record error descriptions carried back to the caller.
        MAX_ERRORS = 10

        # Same minimal shape check the send-test logic uses for recipients.
        EMAIL_PATTERN = Onetime::Utils::EmailFormat::MINIMAL_FORMAT

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
            Onetime::ColonelAuditEvent.record(
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
            Onetime::EmailSuppression.suppress!(address: address, reason: suppression_reason(record), source: source)
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

        # Reason for a 'suppression' import: the record's own reason when it is
        # a valid {Onetime::EmailSuppression::REASONS} value (so a synced SES/
        # Lettermint list keeps bounce vs complaint), else 'manual'.
        def suppression_reason(record)
          reason = field(record, 'reason').to_s
          Onetime::EmailSuppression::REASONS.include?(reason) ? reason : 'manual'
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
