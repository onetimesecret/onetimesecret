# lib/onetime/jobs/queue_declarator.rb
#
# frozen_string_literal: true

require_relative 'queue_config'

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
    #   # Declare all exchanges and queues
    #   QueueDeclarator.declare_all(channel)
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
        #
        # @param channel [Bunny::Channel] Open channel
        # @return [void]
        #
        def declare_all(channel)
          declare_dead_letter_exchanges(channel)
          declare_dead_letter_queues(channel)
          declare_primary_queues(channel)
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
          config = fetch_queue_config!(queue_name)

          # Get the queue_opts from worker class
          worker_opts = begin
            worker_class.queue_opts
          rescue StandardError
            {}
          end
          worker_queue_options = worker_opts[:queue_options] || {}

          errors = []

          # Check durable
          expected_durable = config.fetch(:durable)
          actual_durable = worker_queue_options[:durable]
          if actual_durable != expected_durable
            errors << "durable: expected #{expected_durable}, got #{actual_durable}"
          end

          # Check auto_delete
          expected_auto_delete = config.fetch(:auto_delete)
          actual_auto_delete = worker_queue_options[:auto_delete]
          if actual_auto_delete != expected_auto_delete
            errors << "auto_delete: expected #{expected_auto_delete}, got #{actual_auto_delete}"
          end

          # Check arguments (compare normalized)
          expected_args = normalize_arguments(config.fetch(:arguments, {}))
          actual_args = normalize_arguments(worker_queue_options[:arguments] || {})
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

        # Check if a queue name is valid
        #
        # @param queue_name [String] Queue name to check
        # @return [Boolean]
        #
        def known_queue?(queue_name)
          QueueConfig::QUEUES.key?(queue_name)
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

        def declare_dead_letter_exchanges(channel)
          QueueConfig::DEAD_LETTER_CONFIG.each_key do |exchange_name|
            channel.fanout(exchange_name, durable: true)
            log_debug "Declared DLX '#{exchange_name}'"
          end
        end

        def declare_dead_letter_queues(channel)
          QueueConfig::DEAD_LETTER_CONFIG.each do |exchange_name, config|
            queue = channel.queue(config[:queue], durable: true)
            queue.bind(exchange_name)
            log_debug "Declared and bound DLQ '#{config[:queue]}'"
          end
        end

        def declare_primary_queues(channel)
          QueueConfig::QUEUES.each_key do |queue_name|
            declare_queue(channel, queue_name)
            log_debug "Declared primary queue '#{queue_name}'"
          end
        end

        def normalize_arguments(args)
          # Convert all keys to strings for comparison
          args.transform_keys(&:to_s)
        end

        def log_debug(message)
          Onetime.bunny_logger&.debug("[QueueDeclarator] #{message}")
        end
      end
    end
  end
end
