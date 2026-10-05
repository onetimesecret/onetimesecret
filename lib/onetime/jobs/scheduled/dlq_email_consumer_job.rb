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
      # after the publish and the ack (see #replay_message).
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
        # stays in place if the publish or ack outcome is unknown, and
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
        # publishing form is included only when the publish was never
        # attempted (a lost reply from START_REPLAY_LUA).
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
            conn, channel, own_connection = acquire_channel
            return unless channel

            queue     = channel.queue(DLQ_NAME, durable: true, passive: true)
            available = queue.message_count

            if available == 0
              scheduler_logger.debug '[DlqEmailConsumerJob] DLQ empty'
              return
            end

            to_process = [available, BATCH_SIZE].min
            results    = { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0, deferred: 0 }

            to_process.times do
              delivery_info, properties, payload = queue.pop(manual_ack: true)
              break unless delivery_info

              process_message(channel, delivery_info, properties, payload, results)
              break unless channel.open?
            end

            scheduler_logger.info '[DlqEmailConsumerJob] Batch complete: ' \
                                  "replayed=#{results[:replayed]} " \
                                  "discarded_non_auth=#{results[:discarded_non_auth]} " \
                                  "discarded_expired=#{results[:discarded_expired]} " \
                                  "errors=#{results[:errors]} " \
                                  "deferred=#{results[:deferred]}"
          rescue Bunny::NotFound
            scheduler_logger.debug "[DlqEmailConsumerJob] Queue #{DLQ_NAME} not declared yet"
          ensure
            # Closing the channel returns the messages left unacked (deferred
            # replays) to the DLQ for the next run.
            channel&.close if channel&.open?
            conn&.close if own_connection
          end

          # Use the shared RabbitMQ connection ($rmq_conn) to create a dedicated
          # channel. A dedicated channel (not from $rmq_channel_pool) is used
          # because passive queue declarations and manual_ack operations can
          # trigger channel-level exceptions that would corrupt a pooled channel.
          # Falls back to a standalone connection if the shared one is unavailable.
          #
          # @return [Array(Bunny::Session, Bunny::Channel, Boolean)]
          #   connection, channel, and whether we own the connection (must close it)
          def acquire_channel
            if $rmq_conn&.open?
              [$rmq_conn, $rmq_conn.create_channel, false]
            else
              url  = OT.conf.dig('jobs', 'rabbitmq_url')
              conn = Bunny.new(url)
              conn.start
              [conn, conn.create_channel, true]
            end
          rescue Bunny::TCPConnectionFailed, Bunny::ConnectionTimeout => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Connection failed: #{ex.message}"
            [nil, nil, false]
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
              channel.nack(delivery_info.delivery_tag, false, false)
              results[:discarded_non_auth] += 1
              return
            end

            unless data['data'].nil? || data['data'].is_a?(Hash)
              raise JSON::ParserError, 'Expected template data to be an object'
            end

            # Auth template: check if the token is still valid
            config = AUTH_TEMPLATES[template]
            token  = data.dig('data', config[:token_field])

            unless token
              # No token in payload, can't verify validity
              channel.nack(delivery_info.delivery_tag, false, false)
              results[:discarded_expired] += 1
              return
            end

            if token_expired?(config, token)
              channel.nack(delivery_info.delivery_tag, false, false)
              results[:discarded_expired] += 1
              return
            end

            replay_message(channel, delivery_info, properties, payload, results)
          rescue JSON::ParserError => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Invalid JSON: #{ex.message}"
            channel.nack(delivery_info.delivery_tag, false, false)
            results[:errors] += 1
          rescue StandardError => ex
            scheduler_logger.error "[DlqEmailConsumerJob] Processing deferred: #{ex.class}"
            results[:errors]   += 1
            results[:deferred] += 1
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
          #    with a legacy marker, is deferred.
          # 2. start_replay: switch the reservation to its publishing form
          #    with the one-hour TTL and release the worker's idempotency
          #    claim, so the worker delivers the replay instead of acking it
          #    as a duplicate. The worker's own release is best-effort.
          # 3. finalize_replay, after the publish and the ack: mark the id
          #    completed and drop the reservation.
          #
          # A deferred message is left unacked. Closing the channel at the end
          # of the batch returns it to the DLQ for a later run. It is not
          # nacked with requeue: RabbitMQ can put it back at the head of the
          # DLQ, where this batch would pop it again.
          #
          # A datastore error before the publish never drops the message: the
          # call releases its own reservation (best-effort; otherwise the
          # reservation TTL bounds the wait) and defers. A publish or ack error
          # leaves the outcome unknown, since the copy may be live: the
          # publishing reservation is kept until its TTL expires, and the
          # replay after that can send the email a second time.
          #
          # Publish and ack are separate broker operations here. If they move
          # into an AMQP transaction, finalize only after a confirmed commit.
          def replay_message(channel, delivery_info, properties, payload, results)
            message_id = properties.message_id

            original_queue = extract_original_queue(properties.headers)
            unless original_queue
              scheduler_logger.warn '[DlqEmailConsumerJob] No original queue in x-death headers'
              channel.nack(delivery_info.delivery_tag, false, false)
              results[:errors] += 1
              return
            end

            owner           = SecureRandom.uuid if message_id
            publish_started = false

            if message_id
              reservation = reserve_replay(message_id, owner)
              if reservation == 2
                channel.ack(delivery_info.delivery_tag)
                return
              end

              unless reservation == 1 && start_replay(message_id, owner)
                release_reservation(message_id, owner) if reservation == 1
                defer_replay(message_id, results, 'reservation or legacy marker held')
                return
              end
            end

            publish_started = true

            channel.default_exchange.publish(
              payload,
              routing_key: original_queue,
              persistent: true,
              message_id: message_id,
              content_type: properties.content_type,
              headers: clean_headers(properties.headers),
            )

            channel.ack(delivery_info.delivery_tag)
            results[:replayed] += 1
            finalize_replay(message_id, owner, results) if message_id
          rescue StandardError => ex
            if message_id && owner && !publish_started
              release_reservation(message_id, owner, include_publishing: true)
            end
            reason = if publish_started || reservation == 2
                       'AMQP outcome unknown'
                     else
                       'datastore result unknown; publish not attempted'
                     end
            defer_replay(message_id, results, "#{reason}: #{ex.class}")
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

          # The message is already settled (published and acked), so a
          # failure here is logged and counted, never raised: the publishing
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
            scheduler_logger.error "[DlqEmailConsumerJob] Replay settled but marker finalization unknown: #{ex.class}",
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

          def defer_replay(message_id, results, reason)
            results[:deferred] += 1
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

          def extract_original_queue(headers)
            return nil unless headers

            death = headers['x-death']&.first
            death&.fetch('queue', nil)
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
