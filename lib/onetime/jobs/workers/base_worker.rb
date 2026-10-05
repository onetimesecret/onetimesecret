# lib/onetime/jobs/workers/base_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require 'json'
require_relative '../../utils/retry_helper'
require_relative '../trace_propagation'
require_relative '../queues/config'
require_relative 'envelope'

module Onetime
  module Jobs
    module Workers
      # Base module for RabbitMQ workers (using Kicks gem)
      #
      # Provides common functionality for all workers:
      # - Logging via SemanticLogger (named 'Workers')
      # - Message schema validation
      # - Retry logic with exponential backoff
      # - Dead letter queue handling
      # - Idempotency claims keyed by message id
      #
      # Kicks runs work_with_params on a thread pool against ONE worker
      # instance, so nothing about a message is kept on the worker. Each
      # invocation builds an Envelope from its delivery info and properties
      # and passes it (or a value read from it, such as the message id) to
      # the helpers that need it.
      #
      # Kicks settles a message from the value work_with_params returns, so
      # every path ends in ack!, reject! or requeue!.
      #
      # Example:
      #   class MyWorker
      #     include Sneakers::Worker
      #     include Onetime::Jobs::Workers::BaseWorker
      #
      #     from_queue 'my.queue', ack: true, threads: 4
      #
      #     def work_with_params(msg, delivery_info, metadata)
      #       envelope = Envelope.new(delivery_info, metadata)
      #
      #       with_trace_context(envelope) do
      #         data = decode_message(msg, envelope)
      #         return reject! unless data
      #
      #         unless claim_for_processing(envelope.message_id)
      #           log_info "Skipping duplicate message: #{envelope.message_id}"
      #           return ack!
      #         end
      #         # ... do work ...
      #         ack!
      #       end
      #     end
      #   end
      #
      module BaseWorker
        def self.included(base)
          base.extend(ClassMethods)
          base.include(InstanceMethods)
        end

        module ClassMethods
          # Override to provide worker-specific configuration
          def worker_name
            name.split('::').last # can replace with familia refinement, config_name
          end

          # Override in workers that need boot-time validation of required
          # configuration (credentials, env vars, etc.). Called by WorkerCommand
          # before starting Sneakers. Default is a no-op.
          #
          # @raise [StandardError] if essentials are missing
          def check_essentials!
            # No-op by default
          end
        end

        module InstanceMethods
          # Continue Sentry trace from message headers and wrap processing.
          #
          # Links worker errors and performance data to the originating web
          # request in Sentry. Creates a new transaction if trace headers are
          # absent. Safe to call even if Sentry is not configured.
          #
          # @param envelope [Envelope] the envelope of the message being worked
          # @param name [String] Transaction name (default: "rabbitmq.WorkerClass")
          # @param op [String] Span operation (default: 'queue.process')
          # @yield Block to execute within the transaction
          # @return Result of the block
          def with_trace_context(envelope, name: nil, op: 'queue.process', &)
            transaction_name = name || "rabbitmq.#{worker_name}"

            Onetime::Jobs::TracePropagation.continue_trace(
              envelope.trace_headers,
              name: transaction_name,
              op: op,
              &
            )
          end

          # Parse a message payload and check its schema version. Does not
          # settle the message: Kicks settles from the value work_with_params
          # returns, so the caller rejects with `return reject! unless data`.
          # Every refusal is logged here.
          # @param msg [String] Raw message body
          # @param envelope [Envelope] the envelope of the message being worked
          # @return [Hash, nil] Parsed JSON object with symbol keys, or nil if
          #   the body is not JSON, is not a JSON object (null, array, string,
          #   number, boolean), or the schema version is unknown
          def decode_message(msg, envelope)
            message_id = envelope.message_id
            log_debug 'Parsing message', message_id: message_id, size: msg&.bytesize
            data       = JSON.parse(msg, symbolize_names: true)

            unless envelope.schema_version_known?
              log_error "Unknown schema version: #{envelope.schema_version}", message_id: message_id
              return nil
            end
            return data if data.is_a?(Hash)

            # Every worker reads its payload by key, so only an object is a
            # message. Anything else is refused here, once, for all of them.
            reason = data.nil? ? 'Message payload is null' : 'Message payload is not a JSON object'
            log_error reason, message_id: message_id
            nil
          rescue JSON::ParserError => ex
            log_error "Invalid JSON: #{ex.message}", message_id: message_id
            nil
          end

          # @return [SemanticLogger::Logger] Logger for worker operations
          def logger
            @logger ||= Onetime.get_logger('Workers')
          end

          # Logging helpers with structured data
          def log_info(message, **payload)
            logger.info message, worker: worker_name, **payload
          end

          def log_debug(message, **payload)
            logger.debug message, worker: worker_name, **payload
          end

          def log_error(message, error = nil, **payload)
            if error
              logger.error message,
                worker: worker_name,
                error: error.message,
                error_class: error.class.name,
                backtrace: error.backtrace&.first(5),
                **payload
            else
              logger.error message, worker: worker_name, **payload
            end
          end

          # Flush async log appender to ensure messages are written.
          # Call before reject!/ack! when debugging missing logs.
          def flush_logs
            SemanticLogger.flush if defined?(SemanticLogger)
          rescue StandardError
            # Don't let flush failures break message processing
          end

          def worker_name
            self.class.worker_name
          end

          # Override Kicks' verbose log_msg to produce cleaner output
          # Original includes Thread.current (ugly) and @queue.opts (verbose)
          def log_msg(msg)
            "[#{@id}][#{@queue.name}] #{msg}"
          end

          # Override Kicks' worker_trace to avoid escaped JSON from msg.inspect
          # Shows first 200 chars of payload for debugging without the noise
          def worker_trace(msg)
            # Skip the verbose "Working off:" messages at debug level
            return if msg.start_with?('Working off:') && !ENV['WORKER_TRACE_PAYLOAD']

            logger.debug(log_msg(msg))
          end

          # Retry logic with exponential backoff.
          #
          # Delegates to Onetime::Utils::RetryHelper with worker-specific logging.
          #
          # @param max_retries [Integer] Maximum retry attempts
          # @param base_delay [Float] Base delay in seconds
          # @param retriable [Proc, nil] Optional predicate to check if an error
          #   should be retried. Receives the exception; returns true to retry,
          #   false to re-raise immediately. Defaults to retrying all StandardError.
          #
          # @see Onetime::Utils::RetryHelper#with_retry
          #
          def with_retry(max_retries: 3, base_delay: 1.0, retriable: nil, &)
            Onetime::Utils::RetryHelper.with_retry(
              max_retries: max_retries,
              base_delay: base_delay,
              retriable: retriable,
              logger: logger,
              context: worker_name,
              &
            )
          end

          # A simple predicate to be used as a read-only check only. Hot path
          # code should use claim_for_processing. This is an idempotency check.
          #
          # @param msg_id [String] Message ID to check
          # @return [Boolean] true if already processed
          def already_processed?(msg_id)
            return false unless msg_id

            Familia.dbclient.exists?(Onetime::Jobs::QueueConfig.processing_claim_key(msg_id))
          end

          # Idempotency check.
          # Returns true if this call successfully claimed the message
          # Returns false if already claimed by another worker
          def claim_for_processing(msg_id)
            return false unless msg_id

            ttl = Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
            # Familia.dbclient.set returns true if SET NX succeeded, false if key existed
            Familia.dbclient.set(Onetime::Jobs::QueueConfig.processing_claim_key(msg_id), '1', nx: true, ex: ttl)
          end

          # Release a previously-taken idempotency claim. A failure path that
          # wants the message processed again needs this BEFORE requeue!: the
          # broker redelivers under the same message_id, and within the claim
          # TTL the redelivery is silently ack'd as a duplicate no-op instead
          # of re-running. A message rejected to a DLQ does not need it to be
          # replayed: the operator replay (Onetime::Operations::Dlq::Replay)
          # and the automatic email replay (DlqEmailConsumerJob) release the
          # claim themselves before they republish. Only safe for workers
          # whose work is idempotent. A never-claimed msg_id is a harmless
          # no-op delete. Raises on a datastore error; rescue clauses use
          # release_processing_claim_safely.
          #
          # @param msg_id [String, nil] Message ID whose claim to release
          # @return [Boolean] true if a claim key was deleted
          def release_processing_claim(msg_id)
            return false unless msg_id

            Familia.dbclient.del(Onetime::Jobs::QueueConfig.processing_claim_key(msg_id)).positive?
          end

          # Release an idempotency claim from a failure path without raising.
          # Rescue clauses use this one: a datastore error while releasing is
          # logged and swallowed, so the worker still logs the original error
          # and settles the message with its own reject!/requeue!.
          #
          # The result says whether the claim is gone. A worker that requeues
          # needs true: a redelivery under a claim that is still held is
          # acked as a duplicate, so on false it rejects to the DLQ instead.
          #
          # Call it only when this invocation took the claim (track the result
          # of claim_for_processing in a local). A claim this invocation did
          # not take belongs to another delivery of the same message id.
          #
          # @param msg_id [String, nil] Message ID whose claim to release
          # @return [Boolean] true when no claim is held any more (deleted
          #   now, or already gone); false when the datastore failed and the
          #   claim may still be held
          def release_processing_claim_safely(msg_id)
            release_processing_claim(msg_id)
            true
          rescue StandardError => ex
            log_error "Idempotency claim not released: #{ex.class}", message_id: msg_id
            false
          end
        end
      end
    end
  end
end
