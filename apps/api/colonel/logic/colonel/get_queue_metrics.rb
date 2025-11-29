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

        def raise_concerns; end

        def process
          queues = fetch_queue_stats
          {
            record: {},
            details: {
              connection: connection_info,
              worker_health: worker_health(queues),
              queues: queues
            }
          }
        end

        private

        # Check if RabbitMQ connection is open
        # @return [Hash] Connection status with host info
        def connection_info
          if $rmq_conn&.open?
            {
              connected: true,
              host: extract_host
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
        rescue StandardError
          nil
        end

        # Fetch queue statistics using the existing channel pool
        # Uses passive: true to avoid declaring queues that don't exist
        # @return [Array<Hash>] Queue stats with name, pending_messages, consumers
        def fetch_queue_stats
          return [] unless $rmq_channel_pool

          $rmq_channel_pool.with do |channel|
            Onetime::Jobs::QueueConfig::QUEUES.keys.map do |queue_name|
              fetch_single_queue_stats(channel, queue_name)
            end
          end
        rescue StandardError => e
          OT.le "[GetQueueMetrics] Error fetching queue stats: #{e.message}"
          []
        end

        # Fetch stats for a single queue
        # @param channel [Bunny::Channel] AMQP channel
        # @param queue_name [String] Name of the queue
        # @return [Hash] Queue stats
        def fetch_single_queue_stats(channel, queue_name)
          # passive: true means don't create if doesn't exist
          queue = channel.queue(queue_name, passive: true)
          {
            name: queue_name,
            pending_messages: queue.message_count,
            consumers: queue.consumer_count
          }
        rescue Bunny::NotFound
          # Queue hasn't been declared yet - return zeros
          { name: queue_name, pending_messages: 0, consumers: 0 }
        rescue StandardError => e
          OT.le "[GetQueueMetrics] Error checking queue #{queue_name}: #{e.message}"
          { name: queue_name, pending_messages: 0, consumers: 0 }
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
            active_workers: total_consumers
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
