# lib/onetime/cli/jobs/worker_command.rb
#
# frozen_string_literal: true

#
# CLI command for running Kicks workers (RabbitMQ background processing)
#
# Usage:
#   ots jobs worker [options]
#
# Options:
#   -q, --queues QUEUES          Comma-separated list of queues to process (default: all)
#   -c, --concurrency THREADS    Number of worker threads (default: 10)
#   -d, --daemonize              Run as daemon
#   -e, --environment ENV        Environment to run in (default: development)
#   -l, --log-level LEVEL        Override Jobs logger level (uses logging.yaml by default)
#

require 'sneakers'
require 'sneakers/runner'
require_relative '../../jobs/queue_config'

module Onetime
  module CLI
    module Jobs
      class WorkerCommand < Command
        desc 'Start Kicks job workers'

        option :queues, type: :string, aliases: ['q'],
          desc: 'Comma-separated list of queues to process (default: all)'
        option :concurrency, type: :integer, default: 10, aliases: ['c'],
          desc: 'Number of worker threads'
        option :daemonize, type: :boolean, default: false, aliases: ['d'],
          desc: 'Run as daemon'
        option :environment, type: :string, default: 'development', aliases: ['e'],
          desc: 'Environment to run in'
        option :log_level, type: :string, aliases: ['l'],
          desc: 'Override Jobs logger level (trace/debug/info/warn/error)'

        def call(queues: nil, concurrency: 10, daemonize: false, environment: 'development',
                 log_level: nil, **)
          # Skip RabbitMQ setup during boot - Sneakers creates its own connections.
          # This prevents ConnectionPool.after_fork from timing out when closing
          # inherited channels after Sneakers forks worker processes.
          ENV['SKIP_RABBITMQ_SETUP'] = '1'

          boot_application!

          # Configure Kicks (via Sneakers-compatible API)
          configure_kicks(
            concurrency: concurrency,
            daemonize: daemonize,
            environment: environment,
            log_level: log_level,
          )

          # Determine which worker classes to run
          worker_classes = determine_workers(queues)

          # Declare exchanges and queues
          declare_infrastructure

          if worker_classes.empty?
            Onetime.jobs_logger.error('No worker classes found')
            exit 1
          end

          Onetime.jobs_logger.info("Starting #{worker_classes.size} worker(s) with concurrency #{concurrency}")
          Onetime.jobs_logger.info("Workers: #{worker_classes.map(&:name).join(', ')}")

          # Start heartbeat thread for liveness logging
          start_heartbeat_thread(worker_classes)

          # Start the workers
          runner = Sneakers::Runner.new(worker_classes)
          runner.run
        end

        private

        def declare_infrastructure
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')
          Onetime.bunny_logger.info "[Worker] Initializing RabbitMQ infrastructure..."

          bunny_config = {
            logger: Onetime.get_logger('Bunny'),
          }
          bunny_config.merge!(Onetime::Jobs::QueueConfig.tls_options(amqp_url))

          conn = Bunny.new(amqp_url, **bunny_config)
          conn.start
          channel = conn.create_channel

          # 1. Declare exchanges
          Onetime::Initializers::SetupRabbitMQ.declare_exchanges(channel)

          # 2. Declare and bind queues (including DLQs)
          Onetime::Initializers::SetupRabbitMQ.declare_queues(channel)

          channel.close
          conn.close
        rescue StandardError => ex
          Onetime.bunny_logger.error "[Worker] Failed to initialize infrastructure: #{ex.message}"
        end

        # Periodic heartbeat logging for observability
        # Logs worker status every N minutes so operators can verify the process is alive
        # even when no messages are being processed.
        #
        # @param worker_classes [Array<Class>] Worker classes being run
        def start_heartbeat_thread(worker_classes)
          interval = ENV.fetch('WORKER_HEARTBEAT_INTERVAL', 300).to_i # 5 minutes default
          return if interval <= 0 # Disable with WORKER_HEARTBEAT_INTERVAL=0

          start_time  = Time.now
          queue_names = worker_classes.map(&:queue_name).join(',')

          t                    = Thread.new do
            loop do
              uptime_seconds = (Time.now - start_time).to_i
              uptime_str     = format_uptime(uptime_seconds)

              Onetime.jobs_logger.info(
                "[Worker] Heartbeat | uptime=#{uptime_str} | queues=#{queue_names}",
              )
              sleep interval
            rescue StandardError => ex
              # Don't let heartbeat errors crash the thread
              Onetime.jobs_logger.warn("[Worker] Heartbeat error: #{ex.message}\n#{ex.backtrace&.join("\n")}")
              sleep interval
            end
          end
          t.abort_on_exception = false
          t
        end

        # Format seconds into human-readable uptime string
        # @param seconds [Integer] Total seconds
        # @return [String] Formatted string like "2h15m" or "3d4h"
        def format_uptime(seconds)
          days    = seconds / 86_400
          hours   = (seconds % 86_400) / 3600
          minutes = (seconds % 3600) / 60

          if days > 0
            "#{days}d#{hours}h"
          elsif hours > 0
            "#{hours}h#{minutes}m"
          else
            "#{minutes}m"
          end
        end

        def configure_kicks(concurrency:, daemonize:, environment:, log_level:)
          # Exchange Configuration
          #
          # We use the default exchange (empty string) with direct routing.
          # This matches how Publisher.publish() works - it uses channel.default_exchange
          # which routes messages directly to queues by routing_key (queue name).
          #
          # Why not a custom exchange?
          # - Custom exchanges (e.g., 'onetime-jobs' with topic type) require
          #   explicit queue bindings to route messages
          # - The default exchange automatically binds every queue by its name
          # - Simpler setup: Publisher sends to 'email.message.send', worker
          #   consumes from 'email.message.send' - no binding configuration needed
          #
          # If you need topic-based routing or fan-out in the future, you would:
          # 1. Declare a named exchange in setup_rabbitmq.rb
          # 2. Bind queues to that exchange with routing patterns
          # 3. Update Publisher to use that exchange
          # 4. Update this config to match
          #
          amqp_url = ENV.fetch('RABBITMQ_URL', 'amqp://guest:guest@localhost:5672')

          # Apply CLI log level override if provided
          if log_level
            level_str      = log_level.to_s.downcase
            allowed_levels = %w[trace debug info warn error fatal]
            if allowed_levels.include?(level_str)
              Onetime.jobs_logger.level = level_str.to_sym
            else
              Onetime.jobs_logger.warn(
                "Ignoring invalid log level: #{log_level.inspect}. Allowed: #{allowed_levels.join(', ')}",
              )
            end
          end

          config = {
            amqp: amqp_url,
            exchange: '',
            exchange_type: :direct,
            threads: concurrency,
            workers: 1, # Number of worker processes (vs threads)
            daemonize: daemonize,
            pid_path: ENV.fetch('SNEAKERS_PID_PATH', 'tmp/pids/sneakers.pid'),
            env: environment,
            durable: true,
            ack: true,
            heartbeat: 30,
            prefetch: concurrency,
            # Use Bunny logger from centralized logging config (setup_rabbitmq.rb pattern)
            logger: Onetime.bunny_logger,
          }

          # Override vhost only if explicitly set via env var.
          # Otherwise, let Bunny parse it from the AMQP URL.
          config[:vhost] = ENV['RABBITMQ_VHOST'] if ENV.key?('RABBITMQ_VHOST')

          # TLS configuration for amqps:// connections (centralized in QueueConfig)
          config.merge!(Onetime::Jobs::QueueConfig.tls_options(amqp_url))

          Sneakers.configure(config)
        end

        def determine_workers(queues_str)
          # Auto-discover worker classes in lib/onetime/jobs/workers/
          workers_path = File.join(Onetime::HOME, 'lib', 'onetime', 'jobs', 'workers')
          return [] unless Dir.exist?(workers_path)

          # Load all worker files
          Dir.glob(File.join(workers_path, '**', '*_worker.rb')).each do |file|
            require file
          end

          # Get all worker classes
          worker_classes = ObjectSpace.each_object(Class).select do |klass|
              klass < Sneakers::Worker
          rescue StandardError
              false
          end

          # Filter by queue names if specified
          if queues_str
            queue_names = queues_str.split(',').map(&:strip)
            worker_classes.select! do |worker|
              queue_names.include?(worker.queue_name)
            end
          end

          worker_classes
        end
      end
    end

    register 'jobs worker', Jobs::WorkerCommand
  end
end
