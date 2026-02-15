# apps/api/colonel/logic/colonel/get_queue_metrics.rb
#
# frozen_string_literal: true

require_relative '../base'

module ColonelAPI
  module Logic
    module Colonel
      # Returns RabbitMQ queue metrics for admin dashboard
      #
      # This endpoint is purely passive - it uses the existing $rmq_conn
      # connection established at boot and queries queue stats without
      # creating new connections or impacting workers.
      #
      # Worker health is inferred from consumer count since workers may
      # run on different machines (no PID file access).
      #
      class GetQueueMetrics < ColonelAPI::Logic::Base
        def process_params
          # No parameters needed
        end

        def raise_concerns
          verify_one_of_roles!(colonel: true)
        end

        def process
          queues = fetch_queue_stats
          {
            record: {},
            details: {
              connection: connection_info,
              worker_health: worker_health(queues),
              queues: queues,
            },
          }
        end

        private

        # Check if RabbitMQ connection is open
        # @return [Hash] Connection status with host info
        def connection_info
          if $rmq_conn&.open?
            {
              connected: true,
              host: extract_host,
            }
          else
            { connected: false }
          end
        end

        # Extract host:port from the Bunny connection
        # @return [String] Host and port (e.g., "localhost:5672")
        def extract_host
          return nil unless $rmq_conn

          "#{$rmq_conn.host}:#{$rmq_conn.port}"
        rescue Bunny::Exception
          nil
        end

        # Fetch queue statistics using a temporary channel from $rmq_conn.
        # Uses passive: true to avoid declaring queues that don't exist.
        # A fresh channel is created after Bunny::NotFound (which closes the
        # channel per AMQP spec) so subsequent queues can still be checked.
        # @return [Array<Hash>] Queue stats with name, pending_messages, consumers
        def fetch_queue_stats
          return [] unless $rmq_conn&.open?

          channel = $rmq_conn.create_channel

          Onetime::Jobs::QueueConfig::QUEUES.keys.map do |queue_name|
            fetch_single_queue_stats(channel, queue_name)
          rescue Bunny::NotFound
            # Queue doesn't exist — channel is now closed, reopen for next iteration
            channel = $rmq_conn.create_channel
            { name: queue_name, pending_messages: 0, consumers: 0 }
          rescue Bunny::Exception => ex
            OT.le "[GetQueueMetrics] Error checking queue #{queue_name}: #{ex.message}"
            channel = $rmq_conn.create_channel
            { name: queue_name, pending_messages: 0, consumers: 0 }
          end
        rescue Bunny::Exception => ex
          OT.le "[GetQueueMetrics] Error fetching queue stats: #{ex.message}"
          []
        ensure
          channel&.close if channel&.open?
        end

        # Fetch stats for a single queue
        # @param channel [Bunny::Channel] AMQP channel
        # @param queue_name [String] Name of the queue
        # @return [Hash] Queue stats
        def fetch_single_queue_stats(channel, queue_name)
          queue = channel.queue(queue_name, passive: true)
          {
            name: queue_name,
            pending_messages: queue.message_count,
            consumers: queue.consumer_count,
          }
        end

        # Infer worker health from consumer count
        # @param queues [Array<Hash>] Queue stats
        # @return [Hash] Worker health status
        def worker_health(queues)
          total_consumers = queues.sum { |q| q[:consumers] }
          expected_queues = Onetime::Jobs::QueueConfig::QUEUES.size

          status = determine_health_status(total_consumers, expected_queues)

          {
            status: status,
            active_workers: total_consumers,
          }
        end

        # Determine health status based on consumer count
        # @param total_consumers [Integer] Total consumers across all queues
        # @param expected_queues [Integer] Number of defined queues
        # @return [String] Health status enum
        def determine_health_status(total_consumers, expected_queues)
          return 'unknown' unless $rmq_conn&.open?
          return 'unhealthy' if total_consumers.zero?
          return 'degraded' if total_consumers < expected_queues

          'healthy'
        end
      end
    end
  end
end
