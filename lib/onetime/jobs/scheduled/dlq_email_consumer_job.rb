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
      # Configuration:
      #   jobs:
      #     dlq_consumer_enabled: true
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
            OT.conf.dig('jobs', 'dlq_consumer_enabled') == true
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
            results    = { replayed: 0, discarded_non_auth: 0, discarded_expired: 0, errors: 0 }

            to_process.times do
              delivery_info, properties, payload = queue.pop(manual_ack: true)
              break unless delivery_info

              process_message(channel, delivery_info, properties, payload, results)
            end

            scheduler_logger.info '[DlqEmailConsumerJob] Batch complete: ' \
                                  "replayed=#{results[:replayed]} " \
                                  "discarded_non_auth=#{results[:discarded_non_auth]} " \
                                  "discarded_expired=#{results[:discarded_expired]} " \
                                  "errors=#{results[:errors]}"
          rescue Bunny::NotFound
            scheduler_logger.debug "[DlqEmailConsumerJob] Queue #{DLQ_NAME} not declared yet"
          ensure
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
              url  = OT.conf.dig('jobs', 'rabbitmq_url') ||
                     ENV.fetch('RABBITMQ_URL', 'amqp://localhost:5672')
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

          def replay_message(channel, delivery_info, properties, payload, results)
            message_id = properties.message_id

            # Idempotency: skip if already replayed
            if message_id && !claim_for_replay(message_id)
              channel.ack(delivery_info.delivery_tag)
              return
            end

            original_queue = extract_original_queue(properties.headers)
            unless original_queue
              scheduler_logger.warn '[DlqEmailConsumerJob] No original queue in x-death headers'
              channel.nack(delivery_info.delivery_tag, false, false)
              results[:errors] += 1
              return
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

          # Idempotency claim via Redis SET NX
          # @return [Boolean] true if claimed (first time), false if already seen
          def claim_for_replay(message_id)
            Familia.dbclient.set(
              "dlq:replayed:#{message_id}",
              '1',
              nx: true,
              ex: QueueConfig::IDEMPOTENCY_TTL,
            )
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
