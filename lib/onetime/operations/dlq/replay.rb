# lib/onetime/operations/dlq/replay.rb
#
# frozen_string_literal: true

require 'securerandom'
require 'bunny'
require 'onetime/operations/dlq/store'
require 'onetime/jobs/queues/config'
require 'onetime/jobs/scheduled/dlq_email_consumer_job'
require 'onetime/models/colonel_audit_event'
require 'onetime/audited_failure'
require 'onetime/audit_reason'
require 'onetime/operations/audit_attempt'

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
      # queue (from the `x-death` header) and acks it off the DLQ in one AMQP
      # transaction, so the republished copy and the ack take effect together
      # or not at all. A message with no recoverable original queue is nacked
      # WITHOUT requeue (dropped, to avoid an infinite dead-letter loop) and
      # counted as failed. A message whose publish or ack fails is rolled back
      # and left unacked, and is counted as failed; it returns to the DLQ when
      # the replay closes its channel, so each message is attempted at most
      # once per replay. A commit that fails is counted as failed with an
      # outcome-unknown error and stops the replay: the broker may have
      # applied it.
      #
      # ## A missing original queue
      #
      # A publish to the default exchange "succeeds" when no queue has the
      # routing key's name: the broker drops the message. In the same commit
      # as the DLQ ack, that would lose it. So before republishing, each
      # message's original queue is checked with a passive declare on a
      # separate probe channel (a failed passive declare closes its channel,
      # and the replay channel must stay open). A missing queue is
      # `unroutable`: the message is not republished and stays in the DLQ,
      # counted as failed; the name is remembered for the rest of the run.
      #
      # The check cannot see a queue deleted between it and the commit, so
      # the publish is also `mandatory`: the broker then returns the copy
      # while it applies the commit, before confirming it, and the DLQ ack in
      # that commit has been applied too. The returned message is put back at
      # the end of the DLQ, with its x-death headers, in a commit of its own;
      # if that fails the error says the message may be lost. A publish that
      # is committed alone first (as DlqEmailConsumerJob does) would avoid
      # the window but reopen the one this transaction closes: a copy
      # republished whose DLQ ack then fails is replayed twice.
      #
      # ## Idempotency claims
      #
      # Queue workers take a claim on each message id and skip a later message
      # with the same id as a duplicate (BaseWorker#claim_for_processing). The
      # claim drops broker redeliveries and double publishes. Most workers keep
      # it when they reject a message, and a replay republishes under the
      # original message id, so the worker would ack the replayed message
      # without processing it. A replay is an explicit request to process the
      # message again: the claim on each message id is released before the
      # message is republished. This applies to every queue. A message with no
      # message id has no claim. A message whose claim cannot be released (the
      # datastore is unreachable) is not republished: it is left unacked so it
      # stays in the DLQ, and is counted as failed with the error.
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
      # An operator-supplied `reason:` (#4338) is added to every detail this
      # op writes; without one each detail keeps its pre-#4338 shape.
      #
      # ## One message by id (#4343)
      #
      # With `message_id:` the op replays that one message, with the same
      # steps as each message of a bulk replay (#replay_delivery): claim
      # release, then republish and DLQ ack committed together; a message
      # that is not replayed is left unacked and returns to the DLQ. One
      # difference: a message with no original queue (no x-death) is NOT
      # dropped as the bulk replay drops it. It is left in the DLQ with
      # outcome `no_original_queue`; removing it is Discard's job, where the
      # operator chose destruction.
      # {Store.with_message} finds it with a bounded scan
      # ({Store::MAX_SCAN}) that returns the messages ahead of it to their
      # places, so the rest of the queue keeps its order.
      #
      # A message the scan did not see is NOT_VISIBLE, not absent: the email
      # DLQ consumer holds deliveries unacked during its run, the id may sit
      # deeper than the bound, or the queue may not be declared yet. A live
      # miss records one operator-trail event with `outcome: 'not_visible'`
      # (not fail-closed: nothing moved). A live hit records exactly one
      # event, fail-closed (#4333) whenever the DLQ may have changed.
      #
      # On `dlq.email.message` the replay also takes the
      # {Onetime::Jobs::Scheduled::DlqEmailConsumerJob} reservation on the
      # message id, through the consumer's own scripts, so an operator replay
      # cannot send an email the consumer already sent or is sending. An id
      # marked completed (the consumer republished it within the last hour)
      # is refused as `already_replayed`; an id another replay holds is
      # refused as `replay_in_progress`. Either way nothing is published, the
      # message stays in the DLQ, and the attempt is recorded as a no-change
      # attempt. After a confirmed commit the reservation is released and no
      # completed marker is written: the publish and the DLQ ack commit
      # together here, so the delivery the marker protects (one whose ack
      # failed after its publish) cannot exist, and a marker would make the
      # consumer drop the replayed copy if it fails again within the hour. A
      # commit whose outcome is unknown keeps the reservation until it
      # expires, as the consumer does. The bulk replay does not take this
      # reservation (a known gap, out of scope for #4343).
      #
      # ## Dry run
      #
      # Replay can re-trigger side effects (emails, webhooks). `dry_run: true`
      # reports how many messages WOULD be replayed WITHOUT republishing,
      # acking or releasing a claim — so a caller can preview the blast radius
      # before an explicit live replay (epic #42 note). It writes nothing to the OPERATOR
      # trail, but since #4337 it records one OBSERVATION (`result: 'preview'`)
      # on the budgeted access trail: measuring what a replay would re-fire is
      # reconnaissance. A dry run that finds the queue empty stays an
      # observation too, with `outcome: 'no_change'` added to the preview detail.
      #
      # Stateless, single `#call`, returns an immutable {Result}.
      class Replay
        include Onetime::AuditedFailure
        include Onetime::AuditReason
        include Onetime::Operations::AuditAttempt

        # Audit verb recorded for every replay that processes ≥ 1 message.
        AUDIT_VERB = 'queue.dlq.replay'

        # Per-message refusals on the email DLQ (see the class comment): the
        # #replay_reserved step and the Result/audit outcome.
        ALREADY_REPLAYED   = 'already_replayed'
        REPLAY_IN_PROGRESS = 'replay_in_progress'
        REFUSED_STEPS      = [ALREADY_REPLAYED.to_sym, REPLAY_IN_PROGRESS.to_sym].freeze

        # Per-message outcome for a message with no x-death queue: kept, not
        # dropped (see the class comment).
        NO_ORIGINAL_QUEUE = 'no_original_queue'

        # Per-message outcome when the original queue does not exist (see
        # "A missing original queue").
        UNROUTABLE = 'unroutable'

        # Per-message steps after which nothing moved: the message is still
        # in the DLQ and the attempt is a no-change attempt (#4337), with the
        # step as its outcome.
        NOT_REPLAYED_STEPS = [*REFUSED_STEPS, NO_ORIGINAL_QUEUE.to_sym, UNROUTABLE.to_sym].freeze

        # Per-message steps that moved the message without replaying it: a
        # copy the broker returned as unroutable after the DLQ ack committed.
        RETURNED_STEPS = [:unroutable_restored, :unroutable_lost].freeze

        # The email DLQ consumer whose reservation a per-message replay takes.
        EmailConsumer = Onetime::Jobs::Scheduled::DlqEmailConsumerJob

        # #replay_delivery results after which the channel's transaction
        # state is unknown: the bulk loop stops.
        UNCONFIRMED_STEPS = [:drop_unconfirmed, :commit_unconfirmed, :unroutable_lost].freeze

        # #replay_delivery results after which the DLQ may have changed, so
        # the per-message event is fail-closed (#4333).
        DLQ_CHANGED_STEPS = [:replayed, :dropped, :unroutable_restored, *UNCONFIRMED_STEPS].freeze

        # The bulk path has NO refusal STATUS — `:empty`/`:noop`/`:dry_run` are
        # all honest outcomes, not refusals (the per-message `:refused` is the
        # email DLQ reservation declining, recorded as a no-change attempt).
        # What it DOES have is the nastiest
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
          detail: -> { @message_id ? { dry_run: @dry_run, message_id: @message_id } : { dry_run: @dry_run, count: @count } }

        # @!attribute status [r] Symbol :success (processed ≥ 1) / :empty (queue was
        #   empty) / :noop (queue non-empty but nothing processed) / :dry_run;
        #   per message also :not_visible and :refused
        # @!attribute would_replay [r] Integer dry-run only: messages in scope
        # @!attribute message_id [r] String, nil the id asked for (per message)
        # @!attribute found [r] Boolean, nil the scan saw the id (per message)
        # @!attribute outcome [r] String, nil {Store::NOT_VISIBLE},
        #   {ALREADY_REPLAYED} or {REPLAY_IN_PROGRESS} (per message)
        # @!attribute scanned [r] Integer, nil deliveries the scan popped
        # @!attribute truncated [r] Boolean, nil the scan stopped at its bound
        #   with messages still behind it
        #
        # The per-message members default to nil, so the bulk path builds the
        # same Result it always did.
        Result = Data.define(
          :status,
          :queue,
          :replayed,
          :failed,
          :errors,
          :would_replay,
          :message_id,
          :found,
          :outcome,
          :scanned,
          :truncated,
        ) do
          def initialize(message_id: nil, found: nil, outcome: nil, scanned: nil, truncated: nil, **)
            super
          end
        end

        # @param connection [Object] an already-open Bunny-like connection.
        # @param queue [String] a fully-resolved DLQ name.
        # @param actor [String, #extid, #email] acting admin's PUBLIC identity
        #   (colonel extid/email, or a CLI sentinel). Never an internal objid.
        # @param count [Integer, nil] max messages to replay (nil = all available).
        # @param dry_run [Boolean] preview only — mutates nothing; records one
        #   preview observation on the access trail (#4337), never the operator trail.
        # @param message_id [String, nil] replay only this message (#4343);
        #   exclusive with `count`.
        # @param reason [String, nil] OPTIONAL operator-supplied why (#4338);
        #   blank is absent. See {Onetime::AuditReason}.
        # @param max_scan [Integer] bound on the per-message scan; only the
        #   CLI passes more than {Store::MAX_SCAN}.
        # @raise [ArgumentError] when `count` and `message_id` are both given,
        #   or `message_id` is blank
        def initialize(connection:, queue:, actor:, count: nil, dry_run: false, message_id: nil, reason: nil,
                       max_scan: Store::MAX_SCAN)
          raise ArgumentError, 'count and message_id are exclusive' if count && message_id
          raise ArgumentError, 'message_id must not be blank' if !message_id.nil? && message_id.to_s.strip.empty?

          @connection = connection
          @queue      = queue
          @actor      = actor
          @count      = count
          @dry_run    = dry_run
          @message_id = message_id&.to_s
          @reason     = normalize_reason(reason)
          @max_scan   = max_scan
        end

        # @return [Result]
        def call
          @missing_queues = Set.new
          return replay_one if @message_id

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
              detail: with_reason(replayed: results[:replayed], failed: results[:failed]),
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
          close_probe_channel
        end

        private

        # The #4337 envelope's target hook: the DLQ name, the same target the
        # preview observation, the no-change attempt and the applied event all
        # carry. `audit_verb` defaults to AUDIT_VERB and `audit_actor` to @actor.
        def audit_target = @queue

        # One OBSERVATION per dry run (#4337), on the budgeted access trail.
        # Same verb and target as the applied event so a preview and the replay
        # that followed read as one sequence; `result: 'preview'` and
        # `dry_run: true` distinguish them. Never message contents — only the
        # counts the preview exists to produce. `outcome` is set (to
        # 'no_change') when the preview found the queue already empty.
        def record_preview_event(would_replay, available, outcome: nil)
          detail           = { would_replay: would_replay, available: available }
          detail[:outcome] = outcome if outcome

          record_preview_observation(with_reason(detail))
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
          record_no_change_attempt(with_reason(replayed: 0, failed: 0))
        end

        def empty_result
          Result.new(status: :empty, queue: @queue, replayed: 0, failed: 0, errors: [], would_replay: 0)
        end

        # The release/republish/ack loop. The channel is in transaction mode
        # for its whole life, so every publish, ack and nack takes effect
        # only at tx_commit.
        #
        # A message that is not replayed is left unacked, not nacked with
        # requeue. The broker would put a requeued message back at the head
        # of the DLQ, where the next pop would return it again and use up the
        # attempts meant for the messages behind it. Closing the channel (in
        # #call's ensure) returns every unacked message to the DLQ, also when
        # the loop raises.
        def replay_loop(channel, queue, to_replay)
          results = { replayed: 0, failed: 0, errors: [] }
          channel.tx_select

          to_replay.times do
            delivery_info, properties, payload = queue.pop(manual_ack: true)
            break unless delivery_info

            step = replay_delivery(channel, delivery_info, properties, payload, results)
            # The channel's state is unknown, so the replay stops. The
            # messages not yet popped stay in the DLQ.
            break if UNCONFIRMED_STEPS.include?(step)
          end

          results
        end

        # Replay one popped delivery on a channel in transaction mode: the
        # body of #replay_loop, shared with the per-message path. Counts the
        # outcome into `results` and returns it:
        #
        # - :replayed — republished and acked, committed together.
        # - :dropped — no original queue: nacked without requeue, so it
        #   cannot dead-letter-loop forever, and counted as failed.
        # - :drop_unconfirmed — that drop's commit failed; it may still be
        #   in the DLQ.
        # - :unroutable — no queue has the original name: not republished,
        #   left unacked, counted as failed.
        # - :not_published — the claim was not released, or the publish or
        #   ack failed and was rolled back. Left unacked.
        # - :commit_unconfirmed — the broker did not confirm the commit; the
        #   copy may be live.
        # - :unroutable_restored / :unroutable_lost — the queue went away
        #   after the check: the broker returned the copy after the DLQ ack
        #   committed, and putting the message back in the DLQ succeeded /
        #   failed. Counted as failed.
        def replay_delivery(channel, delivery_info, properties, payload, results)
          original = Store.original_queue(properties.headers)
          unless original
            results[:failed] += 1
            begin
              # Nack WITHOUT requeue — drop, so it can't dead-letter-loop forever.
              channel.nack(delivery_info.delivery_tag, false, false)
              channel.tx_commit
            rescue StandardError => ex
              results[:errors] << { message_id: properties.message_id, error: unconfirmed_drop_error(ex) }
              return :drop_unconfirmed
            end
            results[:errors] << { message_id: properties.message_id, error: 'No original queue found' }
            return :dropped
          end

          unless original_queue_exists?(original)
            results[:failed] += 1
            results[:errors] << { message_id: properties.message_id, error: unroutable_error(original) }
            return :unroutable
          end

          # Release before publishing: a worker can consume the republished
          # message as soon as it is committed.
          begin
            release_processing_claim(properties.message_id)
          rescue StandardError => ex
            results[:failed] += 1
            results[:errors] << {
              message_id: properties.message_id,
              error: "Idempotency claim not released: #{ex.message}",
            }
            # Republished with the claim still held, the message could be
            # acked as a duplicate and lost. Left unacked, it stays in the DLQ.
            return :not_published
          end

          # Set by the channel's reader thread, which handles a return before
          # the commit-ok that tx_commit waits for.
          returned = false
          exchange = channel.default_exchange

          exchange.on_return { |*| returned = true }

          begin
            exchange.publish(
              payload,
              routing_key: original,
              mandatory: true,
              persistent: true,
              message_id: properties.message_id,
              content_type: properties.content_type,
              headers: Store.clean_headers(properties.headers),
            )
            channel.ack(delivery_info.delivery_tag)
          rescue StandardError => ex
            # Discard whatever part of the publish and ack was sent, so the
            # next message's commit cannot carry it. The message stays
            # unacked and returns to the DLQ.
            channel.tx_rollback
            results[:failed] += 1
            results[:errors] << { message_id: properties.message_id, error: ex.message }
            return :not_published
          end

          begin
            channel.tx_commit
          rescue StandardError => ex
            results[:failed] += 1
            results[:errors] << { message_id: properties.message_id, error: unconfirmed_commit_error(original, ex) }
            return :commit_unconfirmed
          end

          return restore_returned(channel, properties, payload, original, results) if returned

          results[:replayed] += 1
          :replayed
        end

        # Passive declare on the probe channel. Only Bunny::NotFound means
        # missing; any other error propagates (the replay cannot tell).
        def original_queue_exists?(name)
          return false if @missing_queues.include?(name)

          probe_channel.queue_declare(name, passive: true)
          true
        rescue Bunny::NotFound
          @missing_queues << name
          false
        end

        # The broker closes a channel whose passive declare fails, so a
        # closed probe channel is replaced.
        def probe_channel
          @probe_channel = @connection.create_channel unless @probe_channel&.open?
          @probe_channel
        end

        def close_probe_channel
          @probe_channel.close if @probe_channel&.open?
        rescue StandardError => ex
          Onetime.get_logger('Operations').warn 'DLQ replay probe channel close failed',
            queue: @queue,
            error_class: ex.class.name
        end

        # The original queue went away between the check and the commit: the
        # copy came back, and the DLQ ack in the same commit is applied. Put
        # the message back at the end of the DLQ, x-death headers and all, in
        # a commit of its own.
        def restore_returned(channel, properties, payload, original, results)
          message_id = properties.message_id

          @missing_queues << original
          results[:failed] += 1

          begin
            channel.default_exchange.publish(
              payload,
              routing_key: @queue,
              persistent: true,
              message_id: message_id,
              content_type: properties.content_type,
              headers: properties.headers || {},
            )
            channel.tx_commit
          rescue StandardError => ex
            results[:errors] << {
              message_id: message_id,
              error: "#{unroutable_error(original, returned: true)} Putting it back in the DLQ failed " \
                     "(#{ex.message}); the message may be lost.",
            }
            return :unroutable_lost
          end

          results[:errors] << {
            message_id: message_id,
            error: "#{unroutable_error(original, returned: true)} It was put back at the end of the DLQ.",
          }
          :unroutable_restored
        end

        # ---- One message by id (#4343) -----------------------------------

        def replay_one
          channel = @connection.create_channel
          scan    = scan_for_message(channel)

          return not_visible(scan) unless scan.found
          return preview_found(scan) if @dry_run

          record_replayed_message(scan)
        ensure
          channel.close if channel&.open?
          close_probe_channel
        end

        # The matched delivery is replayed inside the scan's block, on the
        # scan's channel; a dry run leaves it for channel close. A queue that
        # is configured but not declared on the broker raises Bunny::NotFound
        # from the passive declare, which is a miss like any other.
        def scan_for_message(channel)
          Store.with_message(channel, @queue, @message_id, max_scan: @max_scan) do |delivery_info, properties, payload|
            replay_matched(channel, delivery_info, properties, payload) unless @dry_run
          end
        rescue Bunny::NotFound
          Store::Scan.new(found: false, scanned: 0, truncated: false, value: nil)
        end

        # @return [Hash] { results:, step: }
        def replay_matched(channel, delivery_info, properties, payload)
          results = { replayed: 0, failed: 0, errors: [] }

          # Kept rather than dropped: the operator asked to replay it, not to
          # destroy it. Unacked, it returns to its place when the channel
          # closes.
          unless Store.original_queue(properties.headers)
            results[:errors] << { message_id: properties.message_id, error: no_original_queue_error }
            return { results: results, step: :no_original_queue }
          end

          # Selected after the scan returned the messages ahead of the match,
          # so those nacks were not caught in this transaction.
          channel.tx_select

          step = if email_dlq?
                   replay_reserved(channel, delivery_info, properties, payload, results)
                 else
                   replay_delivery(channel, delivery_info, properties, payload, results)
                 end

          { results: results, step: step }
        end

        # #replay_delivery inside the email DLQ consumer's reservation on the
        # id (see the class comment). Returns its step, or one of
        # REFUSED_STEPS when the reservation refuses.
        def replay_reserved(channel, delivery_info, properties, payload, results)
          message_id = properties.message_id
          owner      = SecureRandom.uuid

          begin
            reservation = reserve_email_replay(message_id, owner)
            started     = reservation == 1 && start_email_replay(message_id, owner)
          rescue StandardError => ex
            # Nothing was published; drop whatever this owner may hold.
            release_email_reservation(message_id, owner)
            results[:failed] += 1
            results[:errors] << { message_id: message_id, error: "Replay reservation not taken: #{ex.message}" }
            return :not_published
          end

          if reservation == 2
            results[:errors] << { message_id: message_id, error: already_replayed_error }
            return :already_replayed
          end

          unless started
            release_email_reservation(message_id, owner) if reservation == 1
            results[:errors] << { message_id: message_id, error: replay_in_progress_error }
            return :replay_in_progress
          end

          step = replay_delivery(channel, delivery_info, properties, payload, results)
          # An unconfirmed commit may have made the copy live: the
          # publishing reservation stays until it expires, holding off the
          # consumer. Every other step leaves no copy the consumer could
          # repeat (or, for :replayed, no DLQ delivery left to repeat).
          release_email_reservation(message_id, owner) unless step == :commit_unconfirmed
          step
        end

        def email_dlq? = @queue == EmailConsumer::DLQ_NAME

        # @return [Integer] 2 completed, 1 reserved by this owner, 0 held elsewhere
        def reserve_email_replay(message_id, owner)
          dbclient.eval(
            EmailConsumer::RESERVE_REPLAY_LUA,
            keys: EmailConsumer.replay_keys(message_id),
            argv: [owner, EmailConsumer::RESERVATION_TTL],
          )
        end

        # Switches the reservation to its publishing form and releases the
        # worker's claim. @return [Boolean] true when this owner may publish
        def start_email_replay(message_id, owner)
          dbclient.eval(
            EmailConsumer::START_REPLAY_LUA,
            keys: [*EmailConsumer.replay_keys(message_id), Onetime::Jobs::QueueConfig.processing_claim_key(message_id)],
            argv: [owner, Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL],
          ) == 1
        end

        # Best effort: a reservation left behind only delays the consumer
        # until its TTL expires.
        def release_email_reservation(message_id, owner)
          dbclient.eval(
            EmailConsumer::RELEASE_RESERVATION_LUA,
            keys: [EmailConsumer.reservation_key(message_id)],
            argv: [owner, '1'],
          )
        rescue StandardError => ex
          Onetime.get_logger('Operations').warn 'DLQ replay reservation not released; it expires on its own',
            queue: @queue,
            message_id: message_id,
            error_class: ex.class.name
        end

        def dbclient = Familia.dbclient

        # A dry run that found the message: one preview observation (#4337).
        def preview_found(scan)
          record_preview_observation(
            with_reason(message_id: @message_id, found: true, would_replay: 1, scanned: scan.scanned),
          )
          message_result(:dry_run, scan, would_replay: 1)
        end

        # A miss, live or dry run. The live one is an attempt on the operator
        # trail under its own outcome; it is not a no-change attempt in the
        # #4337 sense only because "not visible" must not read as "nothing
        # there" (the message may well be there, held by a consumer).
        def not_visible(scan)
          detail = { message_id: @message_id, scanned: scan.scanned, truncated: scan.truncated }
          if @dry_run
            record_preview_observation(
              with_reason(detail.merge(found: false, would_replay: 0, outcome: Store::NOT_VISIBLE)),
            )
          else
            record_not_visible_event(with_reason(detail.merge(replayed: 0, failed: 0)))
          end
          message_result(:not_visible, scan, outcome: Store::NOT_VISIBLE)
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

        # Exactly one event for a live replay that found the message. A
        # refusal moved nothing: a no-change attempt (#4337). Otherwise the
        # counts, fail-closed when the DLQ may have changed (#4333) — a
        # republished or dropped message is the fact the trail must keep.
        def record_replayed_message(scan)
          results = scan.value[:results]
          step    = scan.value[:step]

          if NOT_REPLAYED_STEPS.include?(step)
            record_no_change_attempt(
              with_reason(message_id: @message_id, replayed: 0, failed: 0, refused: step.to_s),
            )
            return message_result(
              :refused, scan, results: { replayed: 0, failed: 0, errors: results[:errors] }, outcome: step.to_s
            )
          end

          return record_returned_message(scan, step, results) if RETURNED_STEPS.include?(step)

          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: :success,
            detail: with_reason(message_id: @message_id, replayed: results[:replayed], failed: results[:failed]),
            fail_closed: DLQ_CHANGED_STEPS.include?(step),
          )
          message_result(:success, scan, results: results)
        end

        # The DLQ changed (acked, then put back at its end, or lost), so the
        # event is fail-closed, carrying the unroutable outcome. Not replayed;
        # failed only when the message may be lost.
        def record_returned_message(scan, step, results)
          counts = { replayed: 0, failed: step == :unroutable_lost ? 1 : 0 }
          Onetime::ColonelAuditEvent.record(
            actor: @actor,
            verb: AUDIT_VERB,
            target: @queue,
            result: :success,
            detail: with_reason(message_id: @message_id, **counts, outcome: UNROUTABLE),
            fail_closed: true,
          )
          message_result(:refused, scan, results: counts.merge(errors: results[:errors]), outcome: UNROUTABLE)
        end

        def message_result(status, scan, results: nil, would_replay: 0, outcome: nil)
          results ||= { replayed: 0, failed: 0, errors: [] }
          Result.new(
            status: status,
            queue: @queue,
            replayed: results[:replayed],
            failed: results[:failed],
            errors: results[:errors],
            would_replay: would_replay,
            message_id: @message_id,
            found: scan.found,
            outcome: outcome,
            scanned: scan.scanned,
            truncated: scan.truncated,
          )
        end

        def already_replayed_error
          'Not republished: the email DLQ consumer already republished this message id within the ' \
            'last hour, so replaying it again would send the email twice. It stays in the DLQ.'
        end

        def unroutable_error(original, returned: false)
          if returned
            "Not replayed: the queue #{original} was deleted during the replay and the broker returned the copy."
          else
            "Not replayed: no queue named #{original} exists, so the republished copy would be dropped. " \
              'It stays in the DLQ until the queue exists again.'
          end
        end

        def no_original_queue_error
          'Not replayed: no original queue recorded (no x-death header), so there is nowhere to ' \
            'republish it. It stays in the DLQ; use Discard to remove it.'
        end

        def replay_in_progress_error
          'Not republished: another replay holds this message id (the email DLQ consumer, or a ' \
            'replay whose outcome is unknown). It stays in the DLQ; try again later.'
        end

        # The broker may have applied the commit before the error reached
        # us, so the republished copy may be live. RabbitMQ does not promise
        # that a commit spanning two queues is applied to both if the broker
        # fails during it, so the DLQ entry may still be there as well.
        def unconfirmed_commit_error(original, ex)
          'Replay stopped, outcome unknown: the broker did not confirm the commit ' \
            "(#{ex.message}). The message may already be republished to #{original}; " \
            'replaying it again may repeat its side effects.'
        end

        def unconfirmed_drop_error(ex)
          'Replay stopped, outcome unknown: the broker did not confirm dropping this message, ' \
            "which has no original queue (#{ex.message}). It may still be in the DLQ."
        end

        # Delete the workers' idempotency claim on a message id, so the worker
        # processes the replayed message. A message id that was never claimed,
        # or whose claim expired or was already released by the worker, is a
        # no-op delete. Raises on a datastore error.
        #
        # @param message_id [String, nil]
        # @return [void]
        def release_processing_claim(message_id)
          return unless message_id

          Familia.dbclient.del(Onetime::Jobs::QueueConfig.processing_claim_key(message_id))
        end
      end
    end
  end
end
