# lib/onetime/jobs/workers/notification_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative '../queue_config'
require_relative '../../operations/dispatch_notification'

#
# Processes notification events from the notifications.alert.push queue.
#
# This worker handles queue consumption, idempotency, and ack/reject logic.
# The actual notification dispatch is delegated to DispatchNotification operation.
#
# Message payload schema:
# {
#   type: 'secret.viewed',         # Event type (secret.viewed, secret.burned, etc.)
#   addressee: {                   # Who receives the notification
#     custid: 'cust:abc123',
#     email: 'user@example.com',
#     webhook_url: 'https://...',  # Optional
#   },
#   template: 'secret_viewed',     # Template name for rendering
#   locale: 'en',                  # Localization
#   channels: ['via_bell', 'via_email'], # Which delivery methods to use
#   data: { ... }                  # Template-specific variables
# }
#

module Onetime
  module Jobs
    module Workers
      class NotificationWorker
        include Sneakers::Worker
        include BaseWorker

        # Queue config from single source of truth (QueueConfig)
        QUEUE_NAME = 'notifications.alert.push'
        QUEUE_OPTS = QueueConfig::QUEUES[QUEUE_NAME]

        from_queue QUEUE_NAME,
          ack: true,
          durable: QUEUE_OPTS[:durable],
          arguments: QUEUE_OPTS[:arguments] || {},
          threads: ENV.fetch('NOTIFICATION_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('NOTIFICATION_WORKER_PREFETCH', 5).to_i

        # Process notification message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          data = parse_message(msg)
          return unless data # parse_message handles reject on error

          # Handle ping test messages (from: bin/ots jobs ping)
          if data[:type] == 'ping.test'
            log_info 'Received ping test', type: data[:type], ping_id: data.dig(:data, :ping_id)
            return ack!
          end

          # Atomic idempotency claim: only one worker can claim a message
          unless claim_for_processing(message_id)
            log_info "Skipping duplicate message: #{message_id}"
            return ack!
          end

          log_debug "Processing notification: #{data[:type]} (metadata: #{message_metadata})"

          # Delegate to operation with retry logic
          with_retry(max_retries: 2, base_delay: 1.0) do
            operation = Onetime::Operations::DispatchNotification.new(
              data: data,
              context: { source_message_id: message_id },
            )
            operation.call
          end

          log_info "Notification dispatched: #{data[:type]}", channels: data[:channels]
          ack!
        rescue StandardError => ex
          log_error 'Unexpected error processing notification', ex
          reject! # Send to DLQ
        end
      end
    end
  end
end
