# lib/onetime/operations/dlq/replay.rb
#
# frozen_string_literal: true

require 'onetime/operations/dlq/store'
require 'onetime/models/admin_audit_event'

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
      # EXACTLY ONE {Onetime::AdminAuditEvent} — verb `queue.dlq.replay`, target the
      # DLQ name, detail the replayed/failed counts. A replay of an empty queue, or
      # one that processed nothing, mutates nothing and records NO event (the "only
      # audit an actual change" rule shared with BanIP / Sessions::Delete).
      #
      # ## Dry run
      #
      # Replay can re-trigger side effects (emails, webhooks). `dry_run: true`
      # reports how many messages WOULD be replayed WITHOUT republishing or acking
      # anything — nothing is mutated and NO audit event is recorded — so a caller
      # can preview the blast radius before an explicit live replay (epic #42 note).
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class Replay
        # Audit verb recorded for every replay that processes ≥ 1 message.
        AUDIT_VERB = 'queue.dlq.replay'

        # @!attribute status [r] Symbol :success (processed ≥ 1) / :empty (queue was
        #   empty) / :noop (queue non-empty but nothing processed) / :dry_run
        # @!attribute would_replay [r] Integer dry-run only: messages in scope
        Result = Data.define(:status, :queue, :replayed, :failed, :errors, :would_replay)

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param count [Integer, nil] max messages to replay (nil = all available).
        # @param dry_run [Boolean] preview only — mutate nothing, audit nothing.
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
            return empty_result
          end

          to_replay = @count ? [@count, available].min : available

          if @dry_run
            return Result.new(
              status: :dry_run, queue: @queue,
              replayed: 0, failed: 0, errors: [], would_replay: to_replay,
            )
          end

          results = replay_loop(channel, queue, to_replay)
          processed = results[:replayed] + results[:failed]

          # Exactly one audit event per replay that actually processed a message.
          if processed.positive?
            Onetime::AdminAuditEvent.record(
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
