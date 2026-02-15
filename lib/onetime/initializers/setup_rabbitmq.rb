# lib/onetime/initializers/setup_rabbitmq.rb
#
# frozen_string_literal: true

require 'bunny'
require 'connection_pool'
require_relative '../jobs/queue_config'
require_relative '../jobs/queue_declarator'

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
    # Fork safety note:
    # ConnectionPool (v2.5+) has automatic fork handling via Process._fork hook.
    # We disable this (auto_reload_after_fork: false) because we manage fork
    # cleanup explicitly via cleanup/reconnect methods called from Puma hooks.
    # See: https://github.com/mperham/connection_pool (ForkTracker module)
    #
    # rubocop:disable Style/GlobalVars
    class SetupRabbitMQ < Onetime::Boot::Initializer
      @depends_on = [:logging]
      @provides   = [:rabbitmq]
      @phase      = :fork_sensitive

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
      # Note: conn.close closes all channels on that connection. This is why we
      # disable ConnectionPool's auto_reload_after_fork - its after_fork handler
      # would try to close already-closed channels, triggering bunny warnings.
      #
      # @return [void]
      def cleanup
        conn              = $rmq_conn
        $rmq_conn         = nil
        $rmq_channel_pool = nil # Clear reference; pool cleanup handled by conn.close

        return unless conn&.open?

        Onetime.bunny_logger.info '[SetupRabbitMQ] Closing RabbitMQ connection before fork'
        conn.close # Closes all channels on this connection
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
          heartbeat: 60, # Keeps connection alive; server closes after 2× interval of silence
          recover_from_connection_close: true,
          network_recovery_interval: 5,
          continuation_timeout: 15_000, # Prevent indefinite hangs if fork hooks misconfigured
          logger: Onetime.get_logger('Bunny'),
        }

        # TLS configuration for amqps:// connections (centralized in QueueConfig)
        # Note: Bunny may warn about missing client certificates when using TLS.
        # This is expected - most managed RabbitMQ services use username/password
        # authentication over TLS, not mutual TLS (client certificates).
        # To silence the warning if client certs are definitely not required:
        #   bunny_config[:tls_cert] = nil
        bunny_config.merge!(Onetime::Jobs::QueueConfig.tls_options(url))

        # Create single connection per process
        $rmq_conn = Bunny.new(url, **bunny_config)

        $rmq_conn.start
        Onetime.bunny_logger.debug '[init] Setup RabbitMQ: connection established'

        # Create channel pool for thread safety
        # Disable auto_reload_after_fork since we handle fork cleanup manually in cleanup/reconnect methods.
        # Otherwise ConnectionPool's automatic after_fork handler will try to close channels
        # that are already closed (from our cleanup), causing "cannot use a closed channel" warnings.
        $rmq_channel_pool = ConnectionPool.new(size: pool_size, timeout: 5, auto_reload_after_fork: false) do
          $rmq_conn.create_channel
        end

        Onetime.bunny_logger.debug "[init] Setup RabbitMQ: channel pool created (size: #{pool_size})"

        # Declare exchanges and queues via QueueDeclarator (single source of truth).
        # Both operations are idempotent - multiple processes declaring the same
        # resources with identical options is safe. We declare from both web and
        # worker processes to handle deployment race conditions where either
        # service may start first.
        declare_exchanges_and_queues

        # Verify connectivity
        # verify_connection

        OT.log_box(
          [
            '✅ RABBITMQ: Connected to message broker',
            "   #{url}",
            "   Pool size: #{pool_size} channels",
            "   Exchanges: #{Onetime::Jobs::QueueConfig::DEAD_LETTER_CONFIG.size} declared",
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

      def declare_exchanges_and_queues
        Onetime::Jobs::QueueDeclarator.declare_all($rmq_conn)
      rescue Onetime::Jobs::QueueDeclarator::InfrastructureError => ex
        Onetime.bunny_logger.error "[init] Setup RabbitMQ: #{ex.message}"
        Onetime.bunny_logger.error '[init] Setup RabbitMQ: Jobs will fall back to synchronous execution'
        # Don't raise - allow app to start with degraded functionality
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
