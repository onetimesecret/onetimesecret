# lib/onetime/jobs/workers/base_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require 'json'

module Onetime
  module Jobs
    module Workers
      # Base module for RabbitMQ workers
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
      #     def work(msg)
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
            name.split('::').last
          end
        end

        module InstanceMethods
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
            version = delivery_info&.properties&.headers&.[]('x-schema-version') || 1

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
          def message_metadata
            {
              delivery_tag: delivery_info&.delivery_tag,
              routing_key: delivery_info&.routing_key,
              redelivered: delivery_info&.redelivered?,
              schema_version: delivery_info&.properties&.headers&.[]('x-schema-version')
            }
          end
        end
      end
    end
  end
end
