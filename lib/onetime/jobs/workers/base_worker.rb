# lib/onetime/jobs/workers/base_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require 'json'

module Onetime
  module Jobs
    module Workers
      # Base module for RabbitMQ workers (using Kicks gem)
      #
      # Provides common functionality for all workers:
      # - Logging with OT.ld/li/le
      # - Message schema validation
      # - Retry logic with exponential backoff
      # - Dead letter queue handling
      #
      # Example:
      #   class MyWorker
      #     include Sneakers::Worker
      #     include Onetime::Jobs::Workers::BaseWorker
      #
      #     from_queue 'my.queue', ack: true, threads: 4
      #
      #     def work_with_params(msg, delivery_info, metadata)
      #       store_envelope(delivery_info, metadata)
      #       data = parse_message(msg)
      #       # ... do work ...
      #       ack!
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
        end

        module InstanceMethods
          # AMQP envelope accessors - set by work_with_params
          # These provide access to delivery_info and metadata from the AMQP envelope
          attr_accessor :delivery_info, :metadata

          # Store AMQP envelope for access by helper methods
          # Call this at the start of work_with_params
          # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
          # @param metadata [Bunny::MessageProperties] AMQP message properties
          def store_envelope(delivery_info, metadata)
            @delivery_info = delivery_info
            @metadata = metadata
          end

          # Parse and validate message payload
          # @param msg [String] Raw message body
          # @return [Hash] Parsed message data
          def parse_message(msg)
            data = JSON.parse(msg, symbolize_names: true)
            validate_schema(data)
            data
          rescue JSON::ParserError => e
            log_error "Invalid JSON: #{e.message}"
            reject!
            nil
          end

          # Validate message schema version
          def validate_schema(data)
            version = @metadata&.headers&.[]('x-schema-version') || 1

            unless Onetime::Jobs::QueueConfig::Versions.const_defined?("V#{version}")
              log_error "Unknown schema version: #{version}"
              reject!
            end
          end

          # Logging helpers
          def log_info(message)
            OT.li "[#{worker_name}] #{message}"
          end

          def log_debug(message)
            OT.ld "[#{worker_name}] #{message}"
          end

          def log_error(message, error = nil)
            OT.le "[#{worker_name}] #{message}"
            if error
              OT.le "[#{worker_name}] Error: #{error.class}: #{error.message}"
              OT.le error.backtrace.join("\n") if OT.debug?
            end
          end

          def worker_name
            self.class.worker_name
          end

          # Retry logic with exponential backoff
          # @param max_retries [Integer] Maximum retry attempts
          # @param base_delay [Float] Base delay in seconds
          def with_retry(max_retries: 3, base_delay: 1.0)
            retries = 0
            begin
              yield
            rescue StandardError => e
              retries += 1
              if retries <= max_retries
                delay = base_delay * (2**(retries - 1))
                log_info "Retry #{retries}/#{max_retries} after #{delay}s: #{e.message}"
                sleep(delay)
                retry
              else
                log_error "Max retries exceeded", e
                reject! # Send to DLQ
              end
            end
          end

          # Extract metadata from message properties
          #
          # NOTE: redelivered? is useful for logging/debugging but not as a
          # substitute for idempotency checks. A message can be delivered
          # exactly once and still be a duplicate (publisher retry before
          # broker ack), and a redelivered message might legitimately need
          # processing (worker crashed before your code ran). The Valkey
          # check remains the source of truth.
          def message_metadata
            {
              delivery_tag: @delivery_info&.delivery_tag,
              routing_key: @delivery_info&.routing_key,
              redelivered: @delivery_info&.redelivered?,
              message_id: message_id,
              schema_version: @metadata&.headers&.[]('x-schema-version')
            }
          end

          # Get message ID from AMQP properties
          # @return [String, nil] The message_id or nil if not present
          def message_id
            @metadata&.message_id
          end

          # A simple predicate to be used as a read-only check only. Hot path
          # code should use claim_for_processing. This is an idempotency check.
          #
          # @param msg_id [String] Message ID to check
          # @return [Boolean] true if already processed
          def already_processed?(msg_id)
            return false unless msg_id
            Familia.dbclient.exists?("job:processed:#{msg_id}")
          end

          # Idempotency check.
          # Returns true if this call successfully claimed the message
          # Returns false if already claimed by another worker
          def claim_for_processing(msg_id)
            return false unless msg_id
            ttl = Onetime::Jobs::QueueConfig::IDEMPOTENCY_TTL
            # Familia.dbclient.set returns true if SET NX succeeded, false if key existed
            Familia.dbclient.set("job:processed:#{msg_id}", '1', nx: true, ex: ttl)
          end
        end
      end
    end
  end
end
