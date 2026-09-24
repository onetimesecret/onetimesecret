# lib/onetime/operations/dlq/replay.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'

module Onetime
  module Operations
    module Dlq
      # Replay (re-enqueue) messages from a dead-letter queue back to their original
      # queue — the SINGLE, audited implementation of the DLQ replay verb (epic #42
      # / D3 / CONTRACT 4). The colonel endpoint (`POST
      # /api/colonel/queues/dlq/:queue/replay`) and the `bin/ots queue dlq replay`
      # CLI are thin adapters over it.
      #
      # This is a mutating verb. For each message it republishes to the original
      # queue (from the `x-death` header) and acks it off the DLQ; a message with no
      # recoverable original queue is nacked WITHOUT requeue (dropped, to avoid an
      # infinite dead-letter loop) and counted as failed; a publish error nacks WITH
      # requeue so the message survives. The republish + ack/nack logic is
      # byte-for-byte the historic CLI `replay_messages`.
      #
      # ## Audit (exactly once)
      #
      # A replay that PROCESSES at least one message (replayed or failed) records
      # EXACTLY ONE {Onetime::ColonelAuditEvent} — verb `queue.dlq.replay`, target the
      # DLQ name, detail the replayed/failed counts. A LIVE replay of an empty
      # queue mutates nothing but is STILL recorded, under the same verb with
      # `outcome: 'no_change'` (#4337): the operator fired the replay verb, and
      # whether a consumer (or an earlier replay) emptied the queue first must
      # not decide whether the trail shows the attempt. A `:noop` run (queue
      # non-empty but the loop processed nothing) still records no event.
      #
      # ## Dry run
      #
      # Replay can re-trigger side effects (emails, webhooks). `dry_run: true`
      # reports how many messages WOULD be replayed WITHOUT republishing or
      # acking anything — so a caller can preview the blast radius before an
      # explicit live replay (epic #42 note). It writes nothing to the OPERATOR
      # trail, but since #4337 it records one OBSERVATION (`result: 'preview'`)
      # on the budgeted access trail: measuring what a replay would re-fire is
      # reconnaissance. A dry run that finds the queue empty stays an
      # observation too, with `outcome: 'no_change'` added to the preview detail.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class Replay
        include Onetime::AuditedFailure

        # Audit verb recorded for every replay that processes ≥ 1 message.
        AUDIT_VERB = 'queue.dlq.replay'

        # This op has NO refusal STATUS — `:empty`/`:noop`/`:dry_run` are all
        # honest outcomes, not refusals. What it DOES have is the nastiest
        # partial-failure shape in the toolbox: the replay loop republishes and
        # acks message by message, each republish able to re-trigger emails and
        # webhooks, and the success record runs only at the end. A broker error
        # halfway through therefore fired real side effects and left NOTHING in
        # the trail. Records one `result: :failure` and re-raises.
        #
        # `dry_run` is in the detail because the success event is
        # applied-path-only: without it a blown-up preview (which sent nothing)
        # is indistinguishable from a blown-up live replay (which may have sent
        # a great deal).
        audit_failures :call,
          verb: AUDIT_VERB,
          target: -> { @queue },
          detail: -> { { dry_run: @dry_run, count: @count } }

        # @!attribute status [r] Symbol :success (processed ≥ 1) / :empty (queue was
        #   empty) / :noop (queue non-empty but nothing processed) / :dry_run
        # @!attribute would_replay [r] Integer dry-run only: messages in scope
        Result = Data.define(:status, :queue, :replayed, :failed, :errors, :would_replay)

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param count [Integer, nil] max messages to replay (nil = all available).
        # @param dry_run [Boolean] preview only — mutates nothing; records one
        #   preview observation on the access trail (#4337), never the operator trail.
        def initialize(connection:, queue:, actor:, count: nil, dry_run: false)
          @connection = connection
          @queue      = queue
          @actor      = actor
          @count      = count
          @dry_run    = dry_run
        end

        # @return [Result]
        def call
          channel = @connection.create_channel
          queue   = Store.queue_handle(channel, @queue)

          available = queue.message_count
          if available.zero?
            # An empty queue mutates nothing, but the attempt still records
            # (#4337), split by intent — this check sits BEFORE the dry-run
            # branch, so both arms land here. A LIVE firing is a mutation
            # attempt (operator trail, outcome: 'no_change'); a dry run stays
            # an observation, with the same marker in the preview detail.
            if @dry_run
              record_preview_event(0, 0, outcome: 'no_change')
            else
              record_no_change_event
            end
            return empty_result
          end

          to_replay = @count ? [@count, available].min : available

          # A dry run re-triggers nothing, so it writes nothing to the OPERATOR
          # trail — but it measures exactly what a replay would re-fire
          # (emails, webhooks), which is reconnaissance worth recording as an
          # OBSERVATION (#4337).
          if @dry_run
            record_preview_event(to_replay, available)
            return Result.new(
              status: :dry_run,
              queue: @queue,
              replayed: 0,
              failed: 0,
              errors: [],
              would_replay: to_replay,
            )
          end

          results   = replay_loop(channel, queue, to_replay)
          processed = results[:replayed] + results[:failed]

          # Exactly one audit event per replay that actually processed a message.
          if processed.positive?
            Onetime::ColonelAuditEvent.record(
              actor: @actor,
              verb: AUDIT_VERB,
              target: @queue,
              result: :success,
              detail: { replayed: results[:replayed], failed: results[:failed] },
            )
          end

          Result.new(
            # :noop (not :empty) when the queue held messages but the loop
            # processed none — so the adapter still prints a results table rather
            # than "No messages", preserving the CLI byte-for-byte.
            status: processed.positive? ? :success : :noop,
            queue: @queue,
            replayed: results[:replayed],
            failed: results[:failed],
            errors: results[:errors],
            would_replay: 0,
          )
        ensure
          channel.close if channel&.open?
        end

        private

        # One OBSERVATION per dry run (#4337), on the budgeted access trail.
        # Same verb and target as the applied event so a preview and the replay
        # that followed read as one sequence; `result: 'preview'` and
        # `dry_run: true` distinguish them. Never message contents — only the
        # counts the preview exists to produce. `outcome` is set (to
        # 'no_change') when the preview found the queue already empty.
        def record_preview_event(would_replay, available, outcome: nil)
          detail           = { dry_run: true, would_replay: would_replay, available: available }
          detail[:outcome] = outcome if outcome

          Onetime::ColonelAuditEvent.record_access(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: 'preview',
            detail: detail,
          )
        end

        # A no-change attempt (#4337) — the OPERATOR trail, not the observation
        # trail. Only the LIVE arm of the empty branch reaches this (the
        # dry-run arm records a preview observation instead), so an empty
        # replay is a live firing of the replay verb that found nothing to
        # re-enqueue — raced by a consumer, or double-fired after an earlier
        # replay or purge. Same verb and target as the applied event, detail
        # mirroring its shape with `outcome: 'no_change'` marking it. NOT
        # fail-closed: nothing was republished or acked, so there is no
        # irrecoverable fact for a hard failure to protect.
        def record_no_change_event
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: :success,
            detail: { outcome: 'no_change', replayed: 0, failed: 0 },
          )
        end

        def empty_result
          Result.new(status: :empty, queue: @queue, replayed: 0, failed: 0, errors: [], would_replay: 0)
        end

        # The republish/ack/nack loop, byte-for-byte the historic CLI.
        def replay_loop(channel, queue, to_replay)
          results = { replayed: 0, failed: 0, errors: [] }

          to_replay.times do
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            original = Store.original_queue(properties.headers)
            unless original
              results[:failed] += 1
              results[:errors] << { message_id: properties.message_id, error: 'No original queue found' }
              # Nack WITHOUT requeue — drop, so it can't dead-letter-loop forever.
              channel.nack(delivery_info.delivery_tag, false, false)
              next
            end

            begin
              channel.default_exchange.publish(
                payload,
                routing_key: original,
                persistent: true,
                message_id: properties.message_id,
                content_type: properties.content_type,
                headers: Store.clean_headers(properties.headers),
              )
              channel.ack(delivery_info.delivery_tag)
              results[:replayed] += 1
            rescue StandardError => ex
              results[:failed] += 1
              results[:errors] << { message_id: properties.message_id, error: ex.message }
              channel.nack(delivery_info.delivery_tag, false, true)
            end
          end

          results
        end
      end
    end
  end
end
