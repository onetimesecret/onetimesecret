# lib/onetime/jobs/scheduled/dlq_email_consumer_job.rb
#
# frozen_string_literal: true

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
      # id before it republishes the message, so the worker delivers the
      # replay instead of acking it as a duplicate (see #replay_message).
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
            scheduler_logger.error "[DlqEmailConsumerJob] Error processing message: #{ex.message}"
            channel.nack(delivery_info.delivery_tag, false, false)
            results[:errors] += 1
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

          # Republish a DLQ message to the queue it was dead-lettered from,
          # once per message id.
          #
          # The worker that rejected the message may still hold its
          # idempotency claim on the id: the worker releases it on the way
          # to the DLQ, but only best-effort. A replay under a held claim is
          # acked by the worker as a duplicate and never sent, so the claim
          # is released here before the message is republished, as the
          # operator replay (Onetime::Operations::Dlq::Replay) does.
          #
          # The claim is released before the message is marked as replayed.
          # When the datastore fails at either step the message is left
          # unacked and unmarked; closing the channel at the end of the batch
          # returns it to the DLQ, and the next run tries again. It is not
          # nacked with requeue: RabbitMQ can put it back at the head of the
          # DLQ, where this batch would pop it again.
          def replay_message(channel, delivery_info, properties, payload, results)
            message_id = properties.message_id

            original_queue = extract_original_queue(properties.headers)
            unless original_queue
              scheduler_logger.warn '[DlqEmailConsumerJob] No original queue in x-death headers'
              channel.nack(delivery_info.delivery_tag, false, false)
              results[:errors] += 1
              return
            end

            if message_id
              begin
                first_replay = claim_replay(message_id)
              rescue StandardError => ex
                scheduler_logger.error "[DlqEmailConsumerJob] Replay deferred to the next run: #{ex.class}",
                  message_id: message_id
                results[:deferred] += 1
                return
              end

              # Idempotency: skip if already replayed
              unless first_replay
                channel.ack(delivery_info.delivery_tag)
                return
              end
            end

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
          end

          # Release the worker's claim on a message id and mark the id as
          # replayed, unless this job already replayed it. The replayed check
          # comes first, so the claim a live copy of a replayed message holds
          # is left alone.
          #
          # @return [Boolean] true if this run is the first to replay it
          # @raise [StandardError] on a datastore error, before the message
          #   id is marked as replayed
          def claim_replay(message_id)
            return false if replayed?(message_id)

            release_processing_claim(message_id)
            claim_for_replay(message_id)
          end

          # Idempotency claim via Redis SET NX
          # @return [Boolean] true if claimed (first time), false if already seen
          def claim_for_replay(message_id)
            Familia.dbclient.set(
              replay_claim_key(message_id),
              '1',
              nx: true,
              ex: QueueConfig::IDEMPOTENCY_TTL,
            )
          end

          # @return [Boolean] true if this job already replayed the message id
          def replayed?(message_id)
            Familia.dbclient.exists?(replay_claim_key(message_id))
          end

          def replay_claim_key(message_id)
            "dlq:replayed:#{message_id}"
          end

          # Delete the worker's idempotency claim on a message id. A message
          # id with no claim (the worker released it, or it expired) is a
          # no-op delete. Raises on a datastore error.
          def release_processing_claim(message_id)
            Familia.dbclient.del(QueueConfig.processing_claim_key(message_id))
          end

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
