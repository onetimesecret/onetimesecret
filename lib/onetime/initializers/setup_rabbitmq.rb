# lib/onetime/initializers/setup_rabbitmq.rb
#
# frozen_string_literal: true

require 'bunny'
require 'connection_pool'

module Onetime
  module Initializers
    # SetupRabbitMQ initializer
    #
    # Configures RabbitMQ connection and channel pool for background job processing.
    # Only runs if jobs are enabled in configuration.
    #
    # Runtime state set:
    # - $rmq_conn: Global Bunny::Session (TCP connection)
    # - $rmq_channel_pool: ConnectionPool of Bunny::Channel objects
    #
    # Puma process architecture:
    # - One TCP connection per process (singleton)
    # - Pool of channels from that connection (thread-safe)
    #
    class SetupRabbitMQ < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides = [:rabbitmq]

      def execute(_context)
        return unless OT.conf.dig('jobs', 'enabled')

        setup_rabbitmq_connection
      end

      private

      def setup_rabbitmq_connection
        url = OT.conf.dig('jobs', 'rabbitmq_url') || ENV.fetch('RABBITMQ_URL', 'amqp://localhost:5672')
        pool_size = OT.conf.dig('jobs', 'channel_pool_size') || ENV.fetch('RABBITMQ_CHANNEL_POOL_SIZE', 5).to_i

        OT.ld "[init] Setup RabbitMQ: connecting to #{sanitize_url(url)}"

        # Create single connection per process
        $rmq_conn = Bunny.new(
          url,
          recover_from_connection_close: true,
          network_recovery_interval: 5,
          logger: OT.logger
        )

        $rmq_conn.start
        OT.ld "[init] Setup RabbitMQ: connection established"

        # Create channel pool for thread safety
        $rmq_channel_pool = ConnectionPool.new(size: pool_size, timeout: 5) do
          $rmq_conn.create_channel
        end

        OT.ld "[init] Setup RabbitMQ: channel pool created (size: #{pool_size})"

        # Declare dead letter infrastructure first (exchanges + queues)
        declare_dead_letter_infrastructure

        # Declare main queues (which reference DLX)
        declare_queues

        # Verify connectivity
        verify_connection

        OT.log_box([
          "✅ RABBITMQ: Connected to message broker",
          "   Pool size: #{pool_size} channels",
          "   Queues: #{Onetime::Jobs::QueueConfig::QUEUES.size} declared"
        ])

        # Set runtime state (optional, for introspection)
        Onetime::Runtime.update_infrastructure(
          rabbitmq_connection: $rmq_conn,
          rabbitmq_channel_pool: $rmq_channel_pool
        )
      rescue Bunny::TCPConnectionFailed, Bunny::ConnectionTimeout => e
        OT.le "[init] Setup RabbitMQ: Connection failed: #{e.message}"
        OT.li "[init] Setup RabbitMQ: Jobs will fall back to synchronous execution"
        # Don't raise - allow app to start with degraded functionality
      rescue StandardError => e
        OT.le "[init] Setup RabbitMQ: Unexpected error: #{e.message}"
        OT.le e.backtrace.join("\n") if OT.debug?
        raise
      end

      def declare_dead_letter_infrastructure
        require_relative '../jobs/queue_config'

        $rmq_channel_pool.with do |channel|
          Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.each do |exchange_name, config|
            # Declare fanout exchange for dead letters
            channel.fanout(exchange_name, durable: true)
            OT.ld "[init] Setup RabbitMQ: Declared DLX '#{exchange_name}'"

            # Declare and bind the dead letter queue
            queue = channel.queue(config[:queue], durable: true)
            queue.bind(exchange_name)
            OT.ld "[init] Setup RabbitMQ: Declared and bound DLQ '#{config[:queue]}'"
          end
        end
      end

      def declare_queues
        require_relative '../jobs/queue_config'

        $rmq_channel_pool.with do |channel|
          Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
            channel.queue(queue_name, **config)
            OT.ld "[init] Setup RabbitMQ: Declared queue '#{queue_name}'"
          end
        end
      end

      def verify_connection
        $rmq_channel_pool.with do |channel|
          # Simple heartbeat check
          channel.queue_exists?('email.immediate')
        end
        OT.ld "[init] Setup RabbitMQ: Connectivity verified"
      rescue StandardError => e
        OT.le "[init] Setup RabbitMQ: Verification failed: #{e.message}"
        raise
      end

      def sanitize_url(url)
        # Hide password in logs
        url.gsub(%r{://([^:]+):([^@]+)@}, '://\1:***@')
      end
    end
  end
end
