# lib/onetime/jobs/workers/transient_worker.rb
#
# frozen_string_literal: true

require_relative 'base_worker'
require_relative '../queue_config'
require_relative '../queue_declarator'

module Onetime
  module Jobs
    module Workers
      # Transient worker for ephemeral system tasks
      #
      # Handles lightweight, non-durable messages like:
      # - Ping tests for queue health checks
      # - Cache invalidation signals
      # - Broadcast notifications
      #
      # Messages in this queue have a 5-minute TTL and the queue itself
      # is auto-delete (removed when last consumer disconnects).
      #
      class TransientWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'system.transient'

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('TRANSIENT_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('TRANSIENT_WORKER_PREFETCH', 5).to_i

        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          data = parse_message(msg)
          return unless data

          # Skip idempotency for transient messages - they're fire-and-forget
          action = data[:action]&.to_sym

          case action
          when :ping
            handle_ping(data)
          else
            log_info "Unknown transient action: #{action}", data: data
          end

          ack!
        rescue StandardError => ex
          log_error 'Error processing transient message', ex
          ack! # Don't reject transient messages - just ack and move on
        end

        private

        def handle_ping(data)
          log_info 'Received ping',
            ping_id: data[:ping_id],
            timestamp: data[:timestamp],
            message_id: message_id
        end
      end
    end
  end
end
