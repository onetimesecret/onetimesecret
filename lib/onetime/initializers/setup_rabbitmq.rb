# lib/onetime/initializers/setup_rabbitmq.rb
#
# frozen_string_literal: true

require 'bunny'
require 'connection_pool'
require_relative '../jobs/queue_config'

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
    # rubocop:disable Style/GlobalVars
    class SetupRabbitMQ < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:rabbitmq]
      @phase      = :fork_sensitive

      class << self
        # @deprecated Use InitializerRegistry.cleanup_before_fork instead
        # This wrapper maintains backward compatibility but will be removed in a future version.
        def disconnect
          warn '[DEPRECATION] SetupRabbitMQ.disconnect is deprecated. Use InitializerRegistry.cleanup_before_fork'
          instance = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.is_a?(SetupRabbitMQ) }
          instance&.cleanup
        end

        # @deprecated Use InitializerRegistry.reconnect_after_fork instead
        # This wrapper maintains backward compatibility but will be removed in a future version.
        def reconnect
          warn '[DEPRECATION] SetupRabbitMQ.reconnect is deprecated. Use InitializerRegistry.reconnect_after_fork'
          instance = Onetime::Boot::InitializerRegistry.initializers.find { |i| i.is_a?(SetupRabbitMQ) }
          instance&.reconnect
        end
      end

      def execute(_context)
        return unless OT.conf.dig('jobs', 'enabled')

        # Workers create their own RabbitMQ connections via Sneakers.
        # Skip setup here to avoid ConnectionPool.after_fork issues when
        # Sneakers forks and tries to close inherited (stale) channels.
        if ENV['SKIP_RABBITMQ_SETUP'] == '1'
          Onetime.bunny_logger.debug '[init] Setup RabbitMQ: Skipped (worker mode - Sneakers handles connections)'
          return
        end

        setup_rabbitmq_connection
      end

      # Cleanup RabbitMQ connection before fork.
      # Called by InitializerRegistry.cleanup_before_fork from Puma's before_fork hook.
      #
      # Always clears global state first - stale connection objects from parent
      # process are useless in forked children.
      #
      # @return [void]
      def cleanup
        conn              = $rmq_conn
        $rmq_conn         = nil
        $rmq_channel_pool = nil

        return unless conn&.open?

        Onetime.bunny_logger.info '[SetupRabbitMQ] Closing RabbitMQ connection before fork'
        conn.close
      rescue StandardError => ex
        Onetime.bunny_logger.warn "[SetupRabbitMQ] Error during cleanup (#{ex.class})"
        Onetime.bunny_logger.debug "[SetupRabbitMQ] Cleanup error details: #{ex.message}"
      end

      # Reconnect RabbitMQ after fork.
      # Called by InitializerRegistry.reconnect_after_fork from Puma's before_worker_boot hook.
      #
      # Creates fresh TCP connection and channel pool in each worker process.
      #
      # @return [void]
      def reconnect
        return unless OT.conf.dig('jobs', 'enabled')

        Onetime.bunny_logger.info "[SetupRabbitMQ] Reconnecting RabbitMQ in worker #{Process.pid}"
        setup_rabbitmq_connection
      rescue Bunny::TCPConnectionFailed, Bunny::ConnectionTimeout => ex
        Onetime.bunny_logger.warn "[SetupRabbitMQ] Reconnect failed (#{ex.class})"
        Onetime.bunny_logger.debug "[SetupRabbitMQ] Reconnect error details: #{ex.message}"
      end

      private

      def setup_rabbitmq_connection
        url       = OT.conf.dig('jobs', 'rabbitmq_url') || ENV.fetch('RABBITMQ_URL', 'amqp://localhost:5672')
        pool_size = OT.conf.dig('jobs', 'channel_pool_size') || ENV.fetch('RABBITMQ_CHANNEL_POOL_SIZE', 5).to_i

        Onetime.bunny_logger.info "[init] RabbitMQ: Connecting to #{sanitize_url(url)}"

        # Build connection configuration
        bunny_config = {
          recover_from_connection_close: true,
          network_recovery_interval: 5,
          continuation_timeout: 15_000, # Prevent indefinite hangs if fork hooks misconfigured
          logger: Onetime.get_logger('Bunny'),
        }

        # TLS configuration for amqps:// connections (centralized in QueueConfig)
        bunny_config.merge!(Onetime::Jobs::QueueConfig.tls_options(url))

        # Create single connection per process
        $rmq_conn = Bunny.new(url, **bunny_config)

        $rmq_conn.start
        Onetime.bunny_logger.debug '[init] Setup RabbitMQ: connection established'

        # Create channel pool for thread safety
        $rmq_channel_pool = ConnectionPool.new(size: pool_size, timeout: 5) do
          $rmq_conn.create_channel
        end

        Onetime.bunny_logger.debug "[init] Setup RabbitMQ: channel pool created (size: #{pool_size})"

        # Declare dead letter infrastructure first (exchanges + queues)
        declare_dead_letter_infrastructure

        # Declare main queues (which reference DLX)
        declare_queues

        # Verify connectivity
        verify_connection

        OT.log_box([
                     '✅ RABBITMQ: Connected to message broker',
                     "   Pool size: #{pool_size} channels",
                     "   Queues: #{Onetime::Jobs::QueueConfig::QUEUES.size} declared",
                   ],
                  )

        # Set runtime state (optional, for introspection)
        Onetime::Runtime.update_infrastructure(
          rabbitmq_connection: $rmq_conn,
          rabbitmq_channel_pool: $rmq_channel_pool,
        )
      rescue Bunny::TCPConnectionFailed, Bunny::ConnectionTimeout, Bunny::PreconditionFailed => ex
        Onetime.bunny_logger.error "[init] Setup RabbitMQ: Connection failed (#{ex.class})"
        Onetime.bunny_logger.debug "[init] Setup RabbitMQ: Connection error details: #{ex.message}"
        Onetime.bunny_logger.error '[init] Setup RabbitMQ: Jobs will fall back to synchronous execution'
        # Don't raise - allow app to start with degraded functionality
      rescue StandardError => ex
        Onetime.bunny_logger.error "[init] Setup RabbitMQ: Unexpected error (#{ex.class})"
        Onetime.bunny_logger.debug "[init] Setup RabbitMQ: Unexpected error details: #{ex.message}"
        Onetime.bunny_logger.error ex.backtrace.join("\n") if OT.debug?
        raise
      end

      def declare_dead_letter_infrastructure
        require_relative '../jobs/queue_config'

        $rmq_channel_pool.with do |channel|
          Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.each do |exchange_name, config|
            # Declare fanout exchange for dead letters
            channel.fanout(exchange_name, durable: true)
            Onetime.bunny_logger.debug "[init] Setup RabbitMQ: Declared DLX '#{exchange_name}'"

            # Declare and bind the dead letter queue
            queue = channel.queue(config[:queue], durable: true)
            queue.bind(exchange_name)
            Onetime.bunny_logger.debug "[init] Setup RabbitMQ: Declared and bound DLQ '#{config[:queue]}'"
          end
        end
      end

      def declare_queues
        require_relative '../jobs/queue_config'

        $rmq_channel_pool.with do |channel|
          Onetime::Jobs::QueueConfig::QUEUES.each do |queue_name, config|
            channel.queue(queue_name, **config)
            Onetime.bunny_logger.debug "[init] Setup RabbitMQ: Declared queue '#{queue_name}'"
          end
        end
      end

      def verify_connection
        $rmq_channel_pool.with do |channel|
          # Verify channel is open and functional
          channel.queue('email.message.send', passive: true)
        end
        Onetime.bunny_logger.debug '[init] Setup RabbitMQ: Connectivity verified'
      rescue Bunny::NotFound
        # Queue doesn't exist yet - that's fine, connection works
        Onetime.bunny_logger.debug '[init] Setup RabbitMQ: Connectivity verified (queue not yet declared)'
      rescue StandardError => ex
        Onetime.bunny_logger.error "[init] Setup RabbitMQ: Verification failed (#{ex.class})"
        Onetime.bunny_logger.debug "[init] Setup RabbitMQ: Verification error details: #{ex.message}"
        raise
      end

      def sanitize_url(url)
        # Hide credentials in logs
        # Handles both user:pass@host and key@host formats
        url.gsub(%r{://([^:@]+):([^@]+)@}, '://\1:***@')  # user:pass@host
          .gsub(%r{://([^/:@]+)@}, '://***@')             # key@host (no colon)
      end
    end
    # rubocop:enable Style/GlobalVars
  end
end
