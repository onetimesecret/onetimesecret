# lib/onetime/jobs/workers/transient_worker.rb
#
# frozen_string_literal: true

require 'sneakers'
require_relative 'base_worker'
require_relative '../queue_config'

module Onetime
  module Jobs
    module Workers
      # Transient event worker for non-critical telemetry
      #
      # Consumes messages from system.transient queue for analytics,
      # metrics, and stats updates. Data loss is acceptable - no retries,
      # no DLQ, no idempotency checks.
      #
      # Message format:
      #   {
      #     "event_type": "domain.verified",
      #     "data": { "domain": "example.com", "organization_id": "abc123" },
      #     "timestamp": "2025-12-11T10:30:00Z"
      #   }
      #
      # Supported event types:
      #   - domain.verified      - Domain TXT record validated
      #   - domain.verification_failed - Verification attempt failed
      #   - domain.added         - New domain registered
      #   - domain.removed       - Domain deleted
      #
      class TransientWorker
        include Sneakers::Worker
        include BaseWorker

        # Queue config from single source of truth (QueueConfig)
        QUEUE_NAME = 'system.transient'
        QUEUE_OPTS = QueueConfig::QUEUES[QUEUE_NAME]

        from_queue QUEUE_NAME,
          ack: true,
          durable: QUEUE_OPTS[:durable],
          arguments: QUEUE_OPTS[:arguments] || {},
          threads: ENV.fetch('TRANSIENT_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('TRANSIENT_WORKER_PREFETCH', 20).to_i

        # Process transient event
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          data = JSON.parse(msg, symbolize_names: true)
          event_type = data[:event_type]

          log_debug "Processing transient event: #{event_type}"

          dispatch_event(event_type, data[:data] || {})

          ack!
        rescue JSON::ParserError => ex
          log_error "Invalid JSON in transient event: #{ex.message}"
          ack! # Discard malformed messages
        rescue StandardError => ex
          log_error 'Error processing transient event', ex
          ack! # Don't retry - just acknowledge and move on
        end

        private

        # Dispatch event to appropriate handler
        # @param event_type [String] Event type
        # @param data [Hash] Event payload
        def dispatch_event(event_type, data)
          case event_type
          when 'domain.verified'
            handle_domain_verified(data)
          when 'domain.verification_failed'
            handle_domain_verification_failed(data)
          when 'domain.added'
            handle_domain_added(data)
          when 'domain.removed'
            handle_domain_removed(data)
          else
            log_debug "Unknown event type: #{event_type}"
          end
        end

        # Handle domain verified event
        def handle_domain_verified(data)
          increment_stat('domains:verified_count')
          log_info 'Domain verified', domain: data[:domain]
        end

        # Handle domain verification failed event
        def handle_domain_verification_failed(data)
          increment_stat('domains:verification_failures')
          log_debug 'Domain verification failed', domain: data[:domain], reason: data[:reason]
        end

        # Handle domain added event
        def handle_domain_added(data)
          increment_stat('domains:total_count')
          log_info 'Domain added', domain: data[:domain]
        end

        # Handle domain removed event
        def handle_domain_removed(data)
          decrement_stat('domains:total_count')
          log_info 'Domain removed', domain: data[:domain]
        end

        # Increment a Redis counter
        # @param key [String] Stats key (will be prefixed with 'stats:')
        def increment_stat(key)
          Familia.redis.incr("stats:#{key}")
        rescue StandardError => ex
          log_error "Failed to increment stat #{key}", ex
        end

        # Decrement a Redis counter
        # @param key [String] Stats key (will be prefixed with 'stats:')
        def decrement_stat(key)
          Familia.redis.decr("stats:#{key}")
        rescue StandardError => ex
          log_error "Failed to decrement stat #{key}", ex
        end
      end
    end
  end
end
