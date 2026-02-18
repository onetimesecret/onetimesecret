# lib/onetime/jobs/queues/declarator.rb
#
# frozen_string_literal: true

require_relative 'config'

module Onetime
  module Jobs
    # Centralized queue declaration service
    #
    # This is the SINGLE SOURCE OF TRUTH for queue declaration logic.
    # All code paths (Puma initializer, CLI commands, workers) MUST use
    # this class to ensure queue options never drift.
    #
    # Why this exists:
    # - RabbitMQ raises PRECONDITION_FAILED when queue options mismatch
    # - Different code paths had different defaults (especially auto_delete)
    # - Workers use Kicks/Sneakers which has deprecated option mapping quirks
    # - This class provides explicit, tested accessors for all use cases
    #
    # Usage:
    #   # Get options for Bunny channel.queue() call
    #   opts = QueueDeclarator.queue_options_for('email.message.send')
    #   channel.queue('email.message.send', **opts)
    #
    #   # Declare a queue via Bunny channel
    #   QueueDeclarator.declare_queue(channel, 'email.message.send')
    #
    #   # Declare all exchanges and queues (pass connection, not channel)
    #   QueueDeclarator.declare_all(conn)
    #
    #   # Get options for Sneakers from_queue directive
    #   from_queue QUEUE_NAME,
    #     **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
    #     threads: 2
    #
    # @see QueueConfig for the underlying queue definitions
    #
    module QueueDeclarator
      class UnknownQueueError < StandardError; end
      class WorkerConfigMismatchError < StandardError; end
      class InfrastructureError < StandardError; end

      class << self
        # Returns Bunny queue options for channel.queue() call
        #
        # @param queue_name [String] Queue name from QueueConfig::QUEUES
        # @return [Hash] Options hash with :durable, :auto_delete, :arguments
        # @raise [UnknownQueueError] if queue_name not in QueueConfig
        #
        # @example
        #   opts = QueueDeclarator.queue_options_for('email.message.send')
        #   channel.queue('email.message.send', **opts)
        #
        def queue_options_for(queue_name)
          config = fetch_queue_config!(queue_name)

          {
            durable: config.fetch(:durable),
            auto_delete: config.fetch(:auto_delete),
            arguments: config.fetch(:arguments, {}),
          }
        end

        # Returns Sneakers from_queue options
        #
        # Note on naming: The Sneakers library is distributed as the "kicks" gem
        # (maintained fork), but the library itself is still called Sneakers.
        # All classes, modules, and methods use the Sneakers namespace.
        #
        # Sneakers has deprecated top-level queue options (durable:, arguments:)
        # and requires a queue_options: hash for proper RabbitMQ queue properties.
        # Critically, top-level auto_delete: is silently ignored - it MUST be
        # in the queue_options: hash. This method returns the correct structure.
        #
        # Note: threads and prefetch are NOT included - those are worker-specific
        # and should be passed separately (often from ENV variables).
        #
        # @param queue_name [String] Queue name from QueueConfig::QUEUES
        # @return [Hash] Options hash with :ack, :queue_options
        # @raise [UnknownQueueError] if queue_name not in QueueConfig
        #
        # @example
        #   from_queue QUEUE_NAME,
        #     **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
        #     threads: ENV.fetch('EMAIL_WORKER_THREADS', 4).to_i,
        #     prefetch: ENV.fetch('EMAIL_WORKER_PREFETCH', 10).to_i
        #
        def sneakers_options_for(queue_name)
          config = fetch_queue_config!(queue_name)

          {
            ack: true,
            queue_options: {
              durable: config.fetch(:durable),
              auto_delete: config.fetch(:auto_delete),
              arguments: config.fetch(:arguments, {}),
            },
          }
        end

        # Declares a single queue on the channel
        #
        # @param channel [Bunny::Channel] Open channel
        # @param queue_name [String] Queue name from QueueConfig::QUEUES
        # @return [Bunny::Queue] The declared queue
        # @raise [UnknownQueueError] if queue_name not in QueueConfig
        #
        def declare_queue(channel, queue_name)
          opts = queue_options_for(queue_name)
          channel.queue(queue_name, **opts)
        end

        # Declares all exchanges and queues defined in QueueConfig
        #
        # Order of operations:
        # 1. Dead letter exchanges (DLX) - must exist before queues reference them
        # 2. Dead letter queues (DLQ) - bound to their exchanges
        # 3. Primary queues - with DLX arguments
        #
        # This is idempotent - safe to call from multiple processes.
        # Each phase uses its own channel so a PreconditionFailed error
        # (which closes the channel) doesn't prevent subsequent declarations.
        #
        # @param conn [Bunny::Session] Open RabbitMQ connection
        # @return [void]
        # @raise [InfrastructureError] if any queues are missing after declaration
        #
        def declare_all(conn)
          errors = []

          declare_dead_letter_exchanges(conn, errors)
          declare_dead_letter_queues(conn, errors)
          declare_primary_queues(conn, errors)

          missing = verify_queues(conn)

          if errors.any? || missing.any?
            errors.each { |e| log_error "Declaration failed: #{e}" }
            missing.each { |q| log_error "Missing after declaration: #{q}" }
            raise InfrastructureError,
              "#{errors.size} declaration error(s), #{missing.size} queue(s) missing: #{missing.join(', ')}. " \
              'Run: bin/ots queue reset --force'
          end

          log_info "All #{QueueConfig::QUEUES.size} queues and " \
                   "#{QueueConfig::DEAD_LETTER_CONFIG.size} DLX exchanges declared"
        end

        # Validates that a worker class configuration matches QueueConfig
        #
        # Checks that the worker's queue_options match what QueueConfig defines.
        # Use this in tests to catch configuration drift early.
        #
        # @param worker_class [Class] Worker class that includes Sneakers::Worker
        # @raise [WorkerConfigMismatchError] if configuration doesn't match
        # @return [true] if configuration is valid
        #
        def validate_worker!(worker_class)
          queue_name = worker_class.queue_name
          config     = fetch_queue_config!(queue_name)

          # Get the queue_opts from worker class
          worker_opts          = begin
            worker_class.queue_opts
          rescue StandardError
            {}
          end
          worker_queue_options = worker_opts[:queue_options] || {}

          errors = []

          # Check durable
          expected_durable = config.fetch(:durable)
          actual_durable   = worker_queue_options[:durable]
          if actual_durable != expected_durable
            errors << "durable: expected #{expected_durable}, got #{actual_durable}"
          end

          # Check auto_delete
          expected_auto_delete = config.fetch(:auto_delete)
          actual_auto_delete   = worker_queue_options[:auto_delete]
          if actual_auto_delete != expected_auto_delete
            errors << "auto_delete: expected #{expected_auto_delete}, got #{actual_auto_delete}"
          end

          # Check arguments (compare normalized)
          expected_args = normalize_arguments(config.fetch(:arguments, {}))
          actual_args   = normalize_arguments(worker_queue_options[:arguments] || {})
          if actual_args != expected_args
            errors << "arguments: expected #{expected_args}, got #{actual_args}"
          end

          unless errors.empty?
            raise WorkerConfigMismatchError,
              "Worker #{worker_class.name} queue config mismatch for '#{queue_name}': #{errors.join(', ')}"
          end

          true
        end

        # List all known queue names
        #
        # @return [Array<String>] Queue names from QueueConfig
        #
        def queue_names
          QueueConfig::QUEUES.keys
        end

        # List all known DLQ names
        #
        # @return [Array<String>] DLQ names from QueueConfig::DEAD_LETTER_CONFIG
        #
        def dlq_names
          QueueConfig::DEAD_LETTER_CONFIG.values.map { |c| c[:queue] }
        end

        # Returns Bunny queue options for a DLQ
        #
        # @param dlq_name [String] DLQ name
        # @return [Hash] Options hash with :durable, :arguments
        # @raise [UnknownQueueError] if dlq_name not found
        #
        def dlq_options_for(dlq_name)
          config = QueueConfig::DEAD_LETTER_CONFIG.values.find { |c| c[:queue] == dlq_name }
          raise UnknownQueueError, "Unknown DLQ: #{dlq_name}" unless config

          {
            durable: true,
            arguments: config.fetch(:arguments, {}),
          }
        end

        # Check if a queue name is valid
        #
        # @param queue_name [String] Queue name to check
        # @return [Boolean]
        #
        def known_queue?(queue_name)
          QueueConfig::QUEUES.key?(queue_name) || dlq_names.include?(queue_name)
        end

        private

        def fetch_queue_config!(queue_name)
          config = QueueConfig::QUEUES[queue_name]

          unless config
            available = QueueConfig::QUEUES.keys.join(', ')
            raise UnknownQueueError,
              "Unknown queue '#{queue_name}'. Available queues: #{available}"
          end

          config
        end

        def declare_dead_letter_exchanges(conn, errors)
          channel = conn.create_channel
          QueueConfig::DEAD_LETTER_CONFIG.each_key do |exchange_name|
            channel.fanout(exchange_name, durable: true)
            log_debug "Declared DLX '#{exchange_name}'"
          rescue Bunny::PreconditionFailed => ex
            errors << "DLX '#{exchange_name}': #{ex.message}"
            log_error "Failed to declare DLX '#{exchange_name}': #{ex.message}"
            channel = conn.create_channel
          end
          channel.close if channel&.open?
        end

        def declare_dead_letter_queues(conn, errors)
          channel = conn.create_channel
          QueueConfig::DEAD_LETTER_CONFIG.each do |exchange_name, config|
            queue_args = config.fetch(:arguments, {})
            queue      = channel.queue(config[:queue], durable: true, arguments: queue_args)
            queue.bind(exchange_name)
            log_debug "Declared and bound DLQ '#{config[:queue]}'"
          rescue Bunny::PreconditionFailed => ex
            errors << "DLQ '#{config[:queue]}': #{ex.message}"
            log_error "Failed to declare DLQ '#{config[:queue]}': #{ex.message}"
            channel = conn.create_channel
          end
          channel.close if channel&.open?
        end

        def declare_primary_queues(conn, errors)
          channel = conn.create_channel
          QueueConfig::QUEUES.each_key do |queue_name|
            declare_queue(channel, queue_name)
            log_debug "Declared primary queue '#{queue_name}'"
          rescue Bunny::PreconditionFailed => ex
            errors << "Queue '#{queue_name}': #{ex.message}"
            log_error "Failed to declare queue '#{queue_name}': #{ex.message}"
            channel = conn.create_channel
          end
          channel.close if channel&.open?
        end

        # Verify all expected primary queues exist after declaration
        #
        # @param conn [Bunny::Session] Open RabbitMQ connection
        # @return [Array<String>] Names of missing queues
        def verify_queues(conn)
          missing = []
          channel = conn.create_channel

          QueueConfig::QUEUES.each_key do |queue_name|
            channel.queue(queue_name, passive: true)
          rescue Bunny::NotFound
            missing << queue_name
            channel = conn.create_channel
          end

          channel.close if channel&.open?
          missing
        end

        def normalize_arguments(args)
          # Convert all keys to strings for comparison
          args.transform_keys(&:to_s)
        end

        def log_debug(message)
          Onetime.bunny_logger&.debug("[QueueDeclarator] #{message}")
        end

        def log_info(message)
          Onetime.bunny_logger&.info("[QueueDeclarator] #{message}")
        end

        def log_error(message)
          Onetime.bunny_logger&.error("[QueueDeclarator] #{message}")
        end
      end
    end
  end
end
