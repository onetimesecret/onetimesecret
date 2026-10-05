# lib/onetime/jobs/scheduled/dlq_email_consumer_job.rb
#
# frozen_string_literal: true

require 'securerandom'

require_relative '../scheduled_job'
require_relative '../queues/config'

module Onetime
  module Jobs
    module Scheduled
      # Consumes messages from the email DLQ and replays auth-critical
      # emails whose tokens are still valid.
      #
      # Non-auth emails (secret_link, expiration_warning, etc.) are discarded
      # because they are time-sensitive and stale by the time they reach the
      # DLQ. Auth emails (password reset, verification, email change) are
      # replayed if the underlying token hasn't expired, because the user
      # is actively waiting for that email.
      #
      # Raw emails (Rodauth's password reset, verify account, email auth)
      # are always replayed since they are auth-critical by definition and
      # their token lifecycle is managed by Rodauth internally.
      #
      # A replay releases the EmailWorker's idempotency claim on the message
      # id right before it republishes the message, so the worker delivers
      # the replay instead of acking it as a duplicate. The id is held by an
      # owned reservation while the replay runs and is marked completed only
      # after the broker confirms the commit of the publish and has not
      # returned the message as unroutable. The DLQ delivery is acked after
      # that (see #replay_message).
      #
      # Configuration:
      #   jobs:
      #     dlq_consumer:
      #       enabled: true
      #
      # Schedule: every 5 minutes, first_in: 30s
      #
      # rubocop:disable Style/GlobalVars
      class DlqEmailConsumerJob < ScheduledJob
        DLQ_NAME   = 'dlq.email.message'
        BATCH_SIZE = 50

        # Seconds a run may spend popping messages, under the 5-minute
        # schedule. A held message is deferred for a reason that another
        # attempt in the same run would not change: another replay has
        # reserved its id, it has a legacy marker, its original queue does
        # not exist, or processing it raised an unexpected error. It is left
        # unacked and does not count against BATCH_SIZE, so held messages at
        # the front of the DLQ do not use up the batch ahead of the messages
        # behind them. Closing the channel returns them to the front of the
        # DLQ, so a run that stopped on a count of held messages would meet
        # the same ones first on every run and never reach the messages
        # behind them. The run is bounded by time instead: a message held
        # for a queue this run already found missing costs no broker or
        # datastore round trip (see #replay_message), so a run passes over
        # any number of them within the budget. Deferrals after a datastore
        # or publish error do count against the batch: each can cost a
        # timeout.
        RUN_BUDGET = 240

        # Ends the batch when a settlement or commit leaves the channel's
        # transaction in an unknown state. Must bypass process_message's
        # error handling: settling another delivery on this channel
        # could commit an earlier, uncertain replay.
        class BatchStopped < StandardError
          attr_reader :message_id

          def initialize(message = nil, message_id: nil)
            super(message)
            @message_id = message_id
          end
        end

        # Seconds a replay reservation lasts before publishing starts.
        RESERVATION_TTL = 300

        # Keys: completed marker, reservation. ARGV: owner, RESERVATION_TTL.
        # Returns 2 when the id is marked completed, 1 when this owner now
        # holds the reservation, 0 when the replay must wait: another owner
        # holds the reservation, or a legacy '1' marker is present. Legacy
        # markers were written before publishing, so they do not prove the
        # replay completed.
        RESERVE_REPLAY_LUA = <<~LUA
          local marker = redis.call('GET', KEYS[1])
          if marker == 'completed' then return 2 end
          if marker then return 0 end
          if redis.call('SET', KEYS[2], ARGV[1], 'NX', 'EX', ARGV[2]) then return 1 end
          return 0
        LUA

        # Keys: completed marker, reservation, worker claim. ARGV: owner,
        # IDEMPOTENCY_TTL. Returns 1 when this owner may publish, 0 when it
        # no longer holds the reservation or the id has a marker. Switches
        # the reservation to its publishing form with the longer TTL, which
        # stays in place if the commit outcome is unknown, and
        # releases the worker's claim so the replayed copy is delivered.
        START_REPLAY_LUA = <<~LUA
          if redis.call('GET', KEYS[2]) ~= ARGV[1] then return 0 end
          if redis.call('EXISTS', KEYS[1]) == 1 then return 0 end
          redis.call('SET', KEYS[2], 'publishing:' .. ARGV[1], 'EX', ARGV[2])
          redis.call('DEL', KEYS[3])
          return 1
        LUA

        # Keys: completed marker, reservation. ARGV: owner, IDEMPOTENCY_TTL.
        # Marks the id completed and drops the reservation, only while this
        # owner still holds the publishing reservation. Returns 1 or 0.
        COMPLETE_REPLAY_LUA = <<~LUA
          if redis.call('GET', KEYS[2]) ~= 'publishing:' .. ARGV[1] then return 0 end
          redis.call('SET', KEYS[1], 'completed', 'EX', ARGV[2])
          redis.call('DEL', KEYS[2])
          return 1
        LUA

        # Keys: reservation. ARGV: owner, '1' to include the publishing form.
        # Deletes the reservation only when this owner holds it. The
        # publishing form is included only when the copy cannot be live: the
        # publish was never attempted (a lost reply from START_REPLAY_LUA),
        # its transaction was not committed, or the broker returned it as
        # unroutable.
        RELEASE_RESERVATION_LUA = <<~LUA
          local reservation = redis.call('GET', KEYS[1])
          if reservation == ARGV[1] or (ARGV[2] == '1' and reservation == 'publishing:' .. ARGV[1]) then
            return redis.call('DEL', KEYS[1])
          end
          return 0
        LUA

        # Auth templates whose DLQ messages are worth replaying.
        # Maps template name to config for token extraction and deadline lookup.
        #
        # token_field:      key in the `data` hash holding the auth token
        # table:            Sequel table to query for deadline
        # key_column:       column containing the token value
        # deadline_column:  column with expiry timestamp (nil = row presence check)
        #
        AUTH_TEMPLATES = {
          'email_change_confirmation' => {
            token_field: 'confirmation_token',
            table: :account_login_change_keys,
            key_column: :key,
            deadline_column: :deadline,
          },
          'password_reset' => {
            token_field: 'account_id',
            table: :account_password_reset_keys,
            key_column: :id,
            deadline_column: :deadline,
          },
          'verify_account' => {
            token_field: 'verify_key',
            table: :account_verification_keys,
            key_column: :key,
            deadline_column: nil,
          },
        }.freeze

        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info '[DlqEmailConsumerJob] Scheduling DLQ email consumer'

            every(scheduler, '5m', first_in: '30s') do
              consume_dlq_batch
            end
          end

          private

          def enabled?
            OT.conf.dig('jobs', 'dlq_consumer', 'enabled') == true
          end

          def consume_dlq_batch
            results                       = new_results
            conn, channel, own_connection = acquire_channel
            return unless channel

            queue     = channel.queue(DLQ_NAME, durable: true, passive: true)
            available = queue.message_count

            if available == 0
              scheduler_logger.debug '[DlqEmailConsumerJob] DLQ empty'
              return
            end

            # Every publish, ack and nack below takes effect only at tx_commit.
            # The channel is dedicated to this batch (#acquire_channel), so
            # transaction mode does not reach other publishers.
            channel.tx_select

            # Held messages stay unacked on this channel, so the broker does
            # not hand them out again during the run and the loop reaches the
            # messages behind them.
            popped   = 0
            deadline = monotonic_now + RUN_BUDGET
            while popped < available && popped - results[:held] < BATCH_SIZE && monotonic_now < deadline
              delivery_info, properties, payload = queue.pop(manual_ack: true)
              break unless delivery_info

              popped += 1
              process_message(channel, delivery_info, properties, payload, results)
              break unless channel.open?
            end

            scheduler_logger.info "[DlqEmailConsumerJob] Batch complete: #{batch_counts(results)}"
          rescue BatchStopped => ex
            # Messages not popped yet stay in the DLQ for the next run.
            scheduler_logger.error "[DlqEmailConsumerJob] #{ex.message}; counts before the stop: #{batch_counts(results)}",
              message_id: ex.message_id
          rescue Bunny::NetworkFailure => ex
            # Bunny can interrupt outside the publish/commit guards. A commit
            # may already have reached the broker; leave reservations untouched.
            scheduler_logger.error "[DlqEmailConsumerJob] Batch stopped: #{ex.class}; outcome may be unknown; counts before the stop: #{batch_counts(results)}"
          rescue Bunny::NotFound
            scheduler_logger.debug "[DlqEmailConsumerJob] Queue #{DLQ_NAME} not declared yet"
          ensure
            # Closing the channel returns the messages left unacked (deferred
            # replays) to the DLQ for the next run.
            begin
              # Transport and reader-loop failures can both interrupt this
              # thread. Finish shutdown (including joining the reader) before
              # handling a second, pending notification of the disconnect.
              Thread.handle_interrupt(Bunny::NetworkFailure => :never) do
                  # A channel-close handshake on a dead transport can recover
                  # the connection even with automatically_recover disabled.
                  channel&.close if channel&.open? && (!own_connection || conn&.open?)
              ensure
                  conn&.close if own_connection
              end
            rescue Bunny::NetworkFailure => ex
              scheduler_logger.error "[DlqEmailConsumerJob] Batch stopped during cleanup: #{ex.class}; outcome may be unknown; counts before the stop: #{batch_counts(results)}"
            end
          end

          # A batch must stay on one broker connection: after automatic recovery,
          # Bunny silently skips acknowledgements of pre-recovery delivery tags.
          # Use an owned, non-recovering connection instead of the shared publisher
          # connection so a disconnect fails the batch rather than reporting a
          # replay whose DLQ delivery was never acknowledged. The next scheduled
          # run opens a fresh connection; shared publisher recovery is unchanged.
          #
          # @return [Array(Bunny::Session, Bunny::Channel, Boolean)]
          #   connection, channel, and whether we own the connection (must close it)
          def acquire_channel
            url     = OT.conf.dig('jobs', 'rabbitmq_url')
            options = {
              automatically_recover: false,
              recover_from_connection_close: false,
              continuation_timeout: 15_000,
              logger: Onetime.get_logger('Bunny'),
            }.merge(QueueConfig.tls_options(url))
            conn    = Bunny.new(url, **options)
            conn.start
            channel = conn.create_channel
            [conn, channel, true]
          rescue Bunny::TCPConnectionFailed, Bunny::ConnectionTimeout => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Connection failed: #{ex.message}"
            [nil, nil, false]
          ensure
            conn&.close unless channel
          end

          # Counters for one run, plus the queue names the broker returned a
          # replay from as unroutable during the run (see #replay_message).
          def new_results
            counters = [:replayed, :discarded_non_auth, :discarded_expired, :errors, :deferred, :held, :unroutable]
            counters.to_h { |name| [name, 0] }.merge(missing_queues: Set.new)
          end

          def batch_counts(results)
            results.filter_map { |name, count| "#{name}=#{count}" if count.is_a?(Integer) }.join(' ')
          end

          def monotonic_now
            Process.clock_gettime(Process::CLOCK_MONOTONIC)
          end

          def process_message(channel, delivery_info, properties, payload, results)
            data = JSON.parse(payload, symbolize_names: false)
            raise JSON::ParserError, 'Expected an email object' unless data.is_a?(Hash)

            # Raw Rodauth emails (password reset, verify account, email auth)
            # are always auth-critical. They have no template field; Rodauth
            # manages their token lifecycle internally.
            if data['raw'] == true
              replay_message(channel, delivery_info, properties, payload, results)
              return
            end

            template = data['template']

            unless template && AUTH_TEMPLATES.key?(template)
              discard_message(channel, delivery_info, properties.message_id)
              results[:discarded_non_auth] += 1
              return
            end

            if data['data'] && !data['data'].is_a?(Hash)
              raise JSON::ParserError, 'Expected template data to be an object'
            end

            # Auth template: check if the token is still valid
            config = AUTH_TEMPLATES[template]
            token  = data.dig('data', config[:token_field])

            unless token
              # No token in payload, can't verify validity
              discard_message(channel, delivery_info, properties.message_id)
              results[:discarded_expired] += 1
              return
            end

            if token_expired?(config, token)
              discard_message(channel, delivery_info, properties.message_id)
              results[:discarded_expired] += 1
              return
            end

            replay_message(channel, delivery_info, properties, payload, results)
          rescue BatchStopped, Bunny::NetworkFailure
            raise
          rescue JSON::ParserError => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Invalid JSON: #{ex.message}"
            discard_message(channel, delivery_info, properties.message_id)
            results[:errors] += 1
          rescue StandardError => ex
            # Not discarded: the error may be a defect in this job, and the
            # message is replayable once that is fixed.
            scheduler_logger.error "[DlqEmailConsumerJob] Processing deferred: #{ex.class}"
            results[:errors]   += 1
            results[:deferred] += 1
            results[:held]     += 1
          end

          # Check whether the auth token has expired by querying the deadline table.
          #
          # @return [Boolean] true if expired or not found
          def token_expired?(config, token)
            db = Auth::Database.connection
            return false unless db

            dataset = db[config[:table]].where(config[:key_column] => token)

            if config[:deadline_column]
              row = dataset.select(config[:deadline_column]).first
              return true unless row

              row[config[:deadline_column]] <= Time.now.utc
            else
              # No deadline column (verify_account): row presence = still valid
              dataset.none?
            end
          rescue StandardError => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Deadline check failed: #{ex.message}"
            false # On error, allow replay (err on the side of delivery)
          end

          # Republish a DLQ message to the queue it was dead-lettered from.
          #
          # A message with an id goes through three datastore steps:
          #
          # 1. reserve_replay: take a short reservation on the id, owned by
          #    this call. An id marked completed is acked without a publish
          #    (the one-hour replay cap). An id reserved by another owner, or
          #    with a legacy marker, is deferred as held: the batch passes
          #    over it without counting it (see RUN_BUDGET).
          # 2. start_replay: switch the reservation to its publishing form
          #    with the one-hour TTL and release the worker's idempotency
          #    claim, so the worker delivers the replay instead of acking it
          #    as a duplicate. The worker's own release is best-effort.
          # 3. finalize_replay, after the broker confirms the commit of the
          #    publish without returning the message: mark the id completed
          #    and drop the reservation.
          #
          # The republish and the ack of the DLQ delivery are committed
          # separately, publish first. A publish to the default exchange
          # succeeds when no queue has the routing key's name; the broker
          # reports that only by returning a mandatory message, and it sends
          # the return when it applies the commit. In one transaction the
          # ack would already be applied by then. So the publish is
          # committed alone, and the delivery is acked only when that commit
          # brought no return.
          #
          # A deferred message is left unacked. Closing the channel at the end
          # of the batch returns it to the DLQ for a later run. It is not
          # nacked with requeue: RabbitMQ can put it back at the head of the
          # DLQ, where this batch would pop it again.
          #
          # No failure drops the message:
          #
          # - Datastore error before the publish: the call releases its own
          #   reservation (best-effort; otherwise the reservation TTL bounds
          #   the wait) and defers.
          # - Publish error: the transaction is rolled back and the
          #   reservation released, so the next run replays the message. A
          #   failed rollback also stops the batch; no commit was sent, so
          #   the copy is not live and the reservation is still released.
          # - Publish commit the broker does not confirm: the copy may or
          #   may not be live. The batch stops and the publishing reservation
          #   is kept. The delivery returns to the DLQ and is replayed once
          #   the reservation expires.
          # - Returned as unroutable (the original queue does not exist): no
          #   copy is live. The reservation is released and the delivery is
          #   left unacked and held, so it is tried again on every run until
          #   the queue exists or the DLQ's message TTL removes it. The queue
          #   name is remembered for the rest of the run, and later messages
          #   for it are held without a reservation or a publish. A queue
          #   recreated during a run is tried again on the next run.
          # - Ack, or its commit, fails after the publish is committed: the
          #   copy is live and the delivery returns to the DLQ. The batch
          #   stops. The id is already marked completed, so the next run
          #   acks the delivery without a second publish. A message without
          #   an id has no marker and is published again.
          def replay_message(channel, delivery_info, properties, payload, results)
            message_id = properties.message_id

            # Without a queue name the message can never be replayed, on this
            # run or a later one, so it is dropped rather than deferred.
            original_queue = extract_original_queue(properties.headers)
            unless original_queue
              scheduler_logger.error '[DlqEmailConsumerJob] No original queue in x-death headers; discarded',
                message_id: message_id
              discard_message(channel, delivery_info, message_id)
              results[:errors] += 1
              return
            end

            if results[:missing_queues].include?(original_queue)
              hold_unroutable(original_queue, message_id, results, known: true)
              return
            end

            owner = SecureRandom.uuid if message_id

            if message_id
              begin
                reservation = reserve_replay(message_id, owner)
                started     = reservation == 1 && start_replay(message_id, owner)
              rescue StandardError => ex
                release_reservation(message_id, owner, include_publishing: true)
                defer_replay(message_id, results, "datastore result unknown; publish not attempted: #{ex.class}")
                return
              end

              # Idempotency: skip if already replayed
              if reservation == 2
                settle(channel, 'duplicate acknowledgement', message_id) { channel.ack(delivery_info.delivery_tag) }
                return
              end

              unless started
                release_reservation(message_id, owner) if reservation == 1
                defer_replay(message_id, results, 'reservation or legacy marker held', held: true)
                return
              end
            end

            # The broker returns the message on this channel's reader thread
            # before it confirms the commit, so the flag is settled by the
            # time tx_commit returns. Only this publish is in the transaction.
            returned = false
            exchange = channel.default_exchange
            exchange.on_return do |*|
              returned = true
            end

            begin
              exchange.publish(
                payload,
                routing_key: original_queue,
                mandatory: true,
                persistent: true,
                message_id: message_id,
                content_type: properties.content_type,
                headers: clean_headers(properties.headers),
              )
            rescue StandardError => ex
              # Nothing is live without a commit, whether or not the rollback
              # succeeds, so the next run may replay this message.
              release_reservation(message_id, owner, include_publishing: true) if message_id

              # Roll back before continuing, otherwise the next message's
              # commit could publish this copy as well.
              begin
                channel.tx_rollback
              rescue StandardError => rollback_error
                stop = "Replay rollback failed; batch stopped: #{rollback_error.class}"
                raise BatchStopped.new(stop, message_id: message_id)
              end
              defer_replay(message_id, results, "rolled back before commit: #{ex.class}")
              return
            end

            # On an unconfirmed commit the publishing reservation stays in
            # place: BatchStopped skips everything below.
            context = "replay to #{original_queue}; the message may already be republished"
            commit_transaction(channel, context, message_id)

            if returned
              release_reservation(message_id, owner, include_publishing: true) if message_id
              results[:missing_queues] << original_queue
              hold_unroutable(original_queue, message_id, results)
              return
            end

            # The copy is live. Mark the id completed before the ack, so a
            # delivery whose ack fails is acked by the next run and not
            # published a second time.
            results[:replayed] += 1
            finalize_replay(message_id, owner, results) if message_id

            settle(channel, 'replay acknowledgement', message_id) { channel.ack(delivery_info.delivery_tag) }
          end

          # Leave a delivery unacked and held because its original queue does
          # not exist. Closing the channel at the end of the run returns it to
          # the DLQ. A queue the run already reported missing is logged at
          # debug level; the batch summary carries the count.
          def hold_unroutable(original_queue, message_id, results, known: false)
            results[:unroutable] += 1
            results[:deferred]   += 1
            results[:held]       += 1

            message = "[DlqEmailConsumerJob] Replay unroutable: no queue named #{original_queue}; left in the DLQ"
            if known
              scheduler_logger.debug message, message_id: message_id
            else
              scheduler_logger.error message, message_id: message_id
            end
          end

          # Drop a delivery from the DLQ (nack without requeue).
          def discard_message(channel, delivery_info, message_id)
            settle(channel, 'discard', message_id) { channel.nack(delivery_info.delivery_tag, false, false) }
          end

          # Settle one delivery and commit it. Transaction mode lasts for the
          # channel's lifetime, so a settlement takes effect only at commit.
          # A settlement that raises stops the batch instead of settling the
          # delivery a second way: the first frame may have reached the broker.
          def settle(channel, context, message_id)
            begin
              yield
            rescue StandardError => ex
              stop = "#{context.capitalize} failed before commit; batch stopped: #{ex.class}"
              raise BatchStopped.new(stop, message_id: message_id)
            end
            commit_transaction(channel, context, message_id)
          end

          # A lost commit reply is not a rollback signal. Stop and close the
          # dedicated channel without trying to settle this delivery again.
          # Each commit covers one publish or one settlement of one delivery.
          def commit_transaction(channel, context, message_id)
            channel.tx_commit
          rescue StandardError => ex
            stop = "Batch stopped, outcome unknown: broker did not confirm #{context} (#{ex.class})"
            raise BatchStopped.new(stop, message_id: message_id)
          end

          # @return [Integer] 2 completed, 1 reserved, 0 deferred
          # @raise [StandardError] on a datastore error
          def reserve_replay(message_id, owner)
            dbclient.eval(RESERVE_REPLAY_LUA, keys: replay_keys(message_id), argv: [owner, RESERVATION_TTL])
          end

          # @return [Boolean] true when this owner may publish
          # @raise [StandardError] on a datastore error
          def start_replay(message_id, owner)
            dbclient.eval(
              START_REPLAY_LUA,
              keys: [*replay_keys(message_id), QueueConfig.processing_claim_key(message_id)],
              argv: [owner, QueueConfig::IDEMPOTENCY_TTL],
            ) == 1
          end

          # The copy is already live (publish committed and not returned), so
          # a failure here is logged and counted, never raised: the publishing
          # reservation then holds off another replay until its TTL expires.
          def finalize_replay(message_id, owner, results)
            completed = dbclient.eval(
              COMPLETE_REPLAY_LUA,
              keys: replay_keys(message_id),
              argv: [owner, QueueConfig::IDEMPOTENCY_TTL],
            ) == 1
            return if completed

            raise 'Replay reservation ownership lost'
          rescue StandardError => ex
            results[:errors] += 1
            scheduler_logger.error "[DlqEmailConsumerJob] Replay published but marker finalization unknown: #{ex.class}",
              message_id: message_id
          end

          def release_reservation(message_id, owner, include_publishing: false)
            dbclient.eval(
              RELEASE_RESERVATION_LUA,
              keys: [reservation_key(message_id)],
              argv: [owner, include_publishing ? '1' : '0'],
            )
          rescue StandardError => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Reservation release unknown; waiting for TTL: #{ex.class}",
              message_id: message_id
          end

          def defer_replay(message_id, results, reason, held: false)
            results[:deferred] += 1
            results[:held]     += 1 if held
            scheduler_logger.warn "[DlqEmailConsumerJob] Replay deferred: #{reason}", message_id: message_id
          end

          def replay_keys(message_id)
            [replayed_marker_key(message_id), reservation_key(message_id)]
          end

          def reservation_key(message_id)
            "dlq:replay:reservation:#{message_id}"
          end

          def replayed_marker_key(message_id)
            "dlq:replayed:#{message_id}"
          end

          # The datastore client. A seam for tests that interleave two runs.
          def dbclient = Familia.dbclient

          # The queue the message was dead-lettered from, read from the
          # first x-death entry. The broker writes x-death as an array of
          # tables; any other shape, or a missing or empty queue name, gives
          # nil.
          #
          # @return [String, nil]
          def extract_original_queue(headers)
            deaths = headers['x-death'] if headers.is_a?(Hash)
            death  = deaths.first if deaths.is_a?(Array)
            queue  = death['queue'] if death.is_a?(Hash)
            queue if queue.is_a?(String) && !queue.empty?
          end

          def clean_headers(headers)
            return {} unless headers

            headers.reject { |k, _| k.start_with?('x-death', 'x-first-death') }
          end
        end
      end
      # rubocop:enable Style/GlobalVars
    end
  end
end
