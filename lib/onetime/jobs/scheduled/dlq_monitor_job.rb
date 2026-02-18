# lib/onetime/jobs/scheduled/dlq_monitor_job.rb
#
# frozen_string_literal: true

require_relative '../scheduled_job'
require_relative '../queues/config'

module Onetime
  module Jobs
    module Scheduled
      # Monitors Dead Letter Queues for unprocessed messages.
      #
      # Runs every 60 seconds and checks the message count of each DLQ
      # using a passive queue declaration (read-only, no consumption).
      # Logs at WARN level when any DLQ has messages, which signals
      # failed deliveries that need investigation or replay.
      #
      # Requires a RabbitMQ connection. Skipped when the job system
      # is not enabled (no $rmq_channel_pool).
      #
      # Enable in config:
      #   jobs:
      #     dlq_monitor_enabled: true
      #
      class DlqMonitorJob < ScheduledJob
        # Check interval in seconds
        INTERVAL = '60s'

        class << self
          def schedule(scheduler)
            return unless enabled?

            scheduler_logger.info '[DlqMonitorJob] Scheduling DLQ depth monitor'

            every(scheduler, INTERVAL, first_in: '15s') do
              check_dlq_depths
            end
          end

          private

          def enabled?
            OT.conf.dig('jobs', 'dlq_monitor_enabled') == true
          end

          def check_dlq_depths
            url  = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
            conn = Bunny.new(url)
            conn.start

            channel        = conn.create_channel
            total_messages = 0

            QueueConfig::DEAD_LETTER_CONFIG.each_value do |config|
              dlq_name = config[:queue]
              count    = queue_message_count(channel, dlq_name)

              next unless count

              total_messages += count
              if count > 0
                scheduler_logger.warn "[DlqMonitorJob] DLQ '#{dlq_name}' has #{count} message(s)"
              end
            rescue Bunny::NotFound
              # Queue not yet declared; open a fresh channel and continue
              scheduler_logger.debug "[DlqMonitorJob] DLQ '#{dlq_name}' not declared yet"
              channel = conn.create_channel
            end

            if total_messages > 0
              scheduler_logger.warn "[DlqMonitorJob] Total DLQ depth: #{total_messages}"
            else
              scheduler_logger.debug '[DlqMonitorJob] All DLQs empty'
            end
          ensure
            channel&.close if channel&.open?
            conn&.close
          end

          # Query message count via passive declaration (read-only)
          # @param channel [Bunny::Channel] Open channel
          # @param dlq_name [String] DLQ queue name
          # @return [Integer, nil] Message count or nil if queue does not exist
          def queue_message_count(channel, dlq_name)
            queue = channel.queue(dlq_name, durable: true, passive: true)
            queue.message_count
          end
        end
      end
    end
  end
end
