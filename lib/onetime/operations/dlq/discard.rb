# lib/onetime/operations/dlq/discard.rb
#
# frozen_string_literal: true

require 'bunny'
require 'onetime/operations/dlq/store'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/audit_attempt'

module Onetime
  module Operations
    module Dlq
      # Discard (permanently drop) ONE message from a dead-letter queue by its
      # AMQP message id — the SINGLE, audited implementation of the DLQ discard
      # verb (#4343). The colonel endpoint (`POST
      # /api/colonel/queues/dlq/:queue/messages/:message_id/discard`) and the
      # `bin/ots queue dlq discard --id` CLI are thin adapters over it.
      #
      # Irreversible message loss, one message at a time: the single-message
      # twin of {Purge}. The adapters gate it the same way (typed confirmation
      # / y-N prompt).
      #
      # {Store.with_message} finds the message with a bounded scan
      # ({Store::MAX_SCAN}) that returns the messages ahead of it to their
      # places before this op touches it, so the rest of the queue keeps its
      # order. The match is acked — removed, never republished — in an AMQP
      # transaction: `basic.ack` has no reply, so the commit is the broker's
      # confirmation that the message is gone, and the audit event is written
      # only after it.
      #
      # ## Audit (exactly once)
      #
      # - Discarded: ONE {Onetime::ColonelAuditEvent} — verb `queue.dlq.discard`,
      #   target the DLQ name, detail the message id and the queue it
      #   originally failed on. FAIL-CLOSED (#4333), as Purge: the message is
      #   gone from the broker and was never mirrored, so this event is the
      #   only surviving fact about it.
      # - Commit not confirmed: the message may or may not be gone (as in the
      #   replay's drop path). ONE event with `result: :failure` and
      #   `outcome: 'unconfirmed'`, also fail-closed.
      # - Not visible: the scan did not see the id (a consumer holds it, it
      #   sits deeper than the bound, or the queue is not declared). A live
      #   miss records ONE operator-trail attempt with `outcome:
      #   'not_visible'`, not fail-closed: nothing was dropped.
      # - Dry run: nothing is acked. ONE observation (`result: 'preview'`) on
      #   the budgeted access trail (#4337), never the operator trail.
      #
      # An operator-supplied `reason:` (#4338) is added to every detail.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class Discard
        include Onetime::AuditedFailure
        include Onetime::AuditReason
        include Onetime::Operations::AuditAttempt

        AUDIT_VERB = 'queue.dlq.discard'

        # Outcome of a discard whose commit the broker did not confirm.
        UNCONFIRMED = 'unconfirmed'

        # A raise from the broker (the scan, or channel setup) is recorded as
        # one `result: :failure` and re-raised. `dry_run` is in the detail so a
        # blown-up preview reads differently from a blown-up live discard.
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @queue },
          detail: -> { { dry_run: @dry_run, message_id: @message_id } }

        # @!attribute status [r] Symbol :success / :dry_run / :not_visible /
        #   :unconfirmed
        # @!attribute found [r] Boolean the scan saw the id
        # @!attribute outcome [r] String, nil {Store::NOT_VISIBLE} or
        #   {UNCONFIRMED}; nil when discarded or previewed
        # @!attribute original_queue [r] String, nil from the x-death header
        # @!attribute scanned [r] Integer deliveries the scan popped
        # @!attribute truncated [r] Boolean the scan stopped at its bound with
        #   messages still behind it
        # @!attribute error [r] String, nil why the outcome is unconfirmed
        Result = Data.define(
          :status,
          :queue,
          :message_id,
          :found,
          :outcome,
          :original_queue,
          :scanned,
          :truncated,
          :error,
        )

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param message_id [String] the AMQP message id to drop.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity.
        # @param dry_run [Boolean] find only — drop nothing; one preview
        #   observation (#4337).
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338).
        # @raise [ArgumentError] when `message_id` is blank
        def initialize(connection:, queue:, message_id:, actor:, dry_run: false, reason: nil)
          raise ArgumentError, 'message_id is required' if message_id.to_s.strip.empty?

          @connection = connection
          @queue      = queue
          @message_id = message_id.to_s
          @actor      = actor
          @dry_run    = dry_run
          @reason     = normalize_reason(reason)
        end

        # @return [Result]
        def call
          channel = @connection.create_channel
          scan    = scan_for_message(channel)

          return not_visible(scan) unless scan.found
          return preview_found(scan) if @dry_run
          return unconfirmed(scan) if scan.value[:error]

          # After the commit: the message is gone, and this event is the only
          # surviving fact about it (#4333).
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: :success,
            detail: with_reason(message_id: @message_id, original_queue: scan.value[:original_queue]),
            fail_closed: true,
          )

          result(:success, scan)
        ensure
          channel.close if channel&.open?
        end

        private

        # The #4337 envelope's target hook: the DLQ name, as for Purge.
        def audit_target = @queue

        # A queue that is configured but not declared on the broker raises
        # Bunny::NotFound from the passive declare: a miss like any other.
        def scan_for_message(channel)
          Store.with_message(channel, @queue, @message_id) do |delivery_info, properties, _payload|
            original = Store.original_queue(properties.headers)
            @dry_run ? { original_queue: original } : drop(channel, delivery_info, original)
          end
        rescue Bunny::NotFound
          Store::Scan.new(found: false, scanned: 0, truncated: false, value: nil)
        end

        # Ack the delivery and commit, so the broker confirms the drop before
        # the event is written. Selected only now: the scan has already
        # returned the messages ahead of this one, outside the transaction.
        # Any error leaves the outcome unknown (the ack may have reached the
        # broker); closing the channel returns the delivery if it did not.
        def drop(channel, delivery_info, original)
          channel.tx_select
          channel.ack(delivery_info.delivery_tag)
          channel.tx_commit
          { original_queue: original }
        rescue StandardError => ex
          { original_queue: original, error: unconfirmed_drop_error(ex) }
        end

        def unconfirmed_drop_error(ex)
          'Discard outcome unknown: the broker did not confirm dropping this message ' \
            "(#{ex.message}). It may still be in the DLQ."
        end

        # The message may be gone, so the attempt is fail-closed like a
        # confirmed discard, but marked as a failure with the unknown outcome.
        def unconfirmed(scan)
          error = scan.value[:error]
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: :failure,
            detail: with_reason(
              message_id: @message_id,
              original_queue: scan.value[:original_queue],
              outcome: UNCONFIRMED,
              error: error,
            ),
            fail_closed: true,
          )
          result(:unconfirmed, scan, outcome: UNCONFIRMED, error: error)
        end

        # One OBSERVATION per dry run (#4337): the preview names the message
        # an operator is about to destroy, which is reconnaissance.
        def preview_found(scan)
          record_preview_observation(
            with_reason(
              message_id: @message_id,
              found: true,
              original_queue: scan.value[:original_queue],
              scanned: scan.scanned,
            ),
          )
          result(:dry_run, scan)
        end

        # A miss, live or dry run. The live one is an attempt on the operator
        # trail under its own outcome; "not visible" must not read as
        # "nothing there", which `outcome: 'no_change'` would.
        def not_visible(scan)
          detail = { message_id: @message_id, scanned: scan.scanned, truncated: scan.truncated }
          if @dry_run
            record_preview_observation(with_reason(detail.merge(found: false, outcome: Store::NOT_VISIBLE)))
          else
            record_not_visible_event(with_reason(detail))
          end
          result(:not_visible, scan, outcome: Store::NOT_VISIBLE)
        end

        def record_not_visible_event(detail)
          Onetime::ColonelAuditEvent.record(
            actor: audit_actor,
            verb: audit_verb,
            target: audit_target,
            result: :success,
            detail: detail.merge(outcome: Store::NOT_VISIBLE),
          )
        end

        def result(status, scan, outcome: nil, error: nil)
          Result.new(
            status: status,
            queue: @queue,
            message_id: @message_id,
            found: scan.found,
            outcome: outcome,
            original_queue: scan.value&.dig(:original_queue),
            scanned: scan.scanned,
            truncated: scan.truncated,
            error: error,
          )
        end
      end
    end
  end
end
