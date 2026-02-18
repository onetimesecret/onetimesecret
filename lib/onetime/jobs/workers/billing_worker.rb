# lib/onetime/jobs/workers/billing_worker.rb
#
# frozen_string_literal: true

require 'stripe'
require_relative 'base_worker'
require_relative '../queues/config'
require_relative '../queues/declarator'
require_relative '../../../../apps/web/billing/operations/process_webhook_event'
require_relative '../../../../apps/web/billing/models/stripe_webhook_event'

# ==========================================================================
# WORKER STRIPE INITIALIZATION
# ==========================================================================
# The worker runs in a separate process from the web app, so it needs to
# configure Stripe independently. The web app's StripeSetup initializer
# may not run in worker context depending on billing config state.
#
# This ensures Stripe API is always available for billing event processing.
# ==========================================================================
if Stripe.api_key.nil? || Stripe.api_key.to_s.strip.empty?
  stripe_key = Onetime.billing_config&.stripe_key
  if stripe_key && !stripe_key.to_s.strip.empty?
    Stripe.api_key     = stripe_key
    Stripe.api_version = Onetime.billing_config&.stripe_api_version
    Onetime.workers_logger&.info '[BillingWorker] Stripe API configured for worker'
  else
    Onetime.workers_logger&.warn '[BillingWorker] No Stripe API key found - billing events will fail'
  end
end

#
# Processes Stripe webhook events from the billing.event.process queue.
#
# This worker enables asynchronous processing of Stripe webhooks, allowing
# the web process to return immediately after signature validation and
# event storage, eliminating data loss risk on processing errors.
#
# The webhook controller validates the signature, enqueues the raw payload,
# and returns 200. This worker then processes the event at its own pace
# with retry logic and DLQ handling.
#
# Message payload schema:
# {
#   event_id: 'evt_xxx',           # Stripe event ID (used for idempotency)
#   event_type: 'checkout.session.completed',  # Event type for logging
#   payload: '{"id":"evt_xxx"...}', # Raw JSON payload from Stripe
#   received_at: '2024-01-01T00:00:00Z',  # When webhook was received
# }
#
# ## Retry Strategy: Internal vs Broker-Based
#
# This worker uses internal retry (with_retry) rather than broker redelivery.
#
# Rationale:
# - Current infrastructure has DLX/DLQ but no retry queues with TTL
# - Broker-based retry would require: retry queues, TTL config, header-based
#   retry counting, and routing back to main queue after delay
# - Internal retry is faster for transient errors (Stripe API blips resolve
#   in seconds) - no broker round-trip overhead
# - Thread blocking during sleep is acceptable for short delays (2-8s)
#
# Reconsider broker-based retry when:
# - Retry delays need to exceed 30 seconds (holding thread too long)
# - Retry visibility in monitoring dashboards becomes important
# - Retry queue infrastructure is added for other workers
# - Worker crashes during retry become a recurring problem
#

module Onetime
  module Jobs
    module Workers
      class BillingWorker
        include Sneakers::Worker
        include BaseWorker

        QUEUE_NAME = 'billing.event.process'

        from_queue QUEUE_NAME,
          **QueueDeclarator.sneakers_options_for(QUEUE_NAME),
          threads: ENV.fetch('BILLING_WORKER_THREADS', 2).to_i,
          prefetch: ENV.fetch('BILLING_WORKER_PREFETCH', 5).to_i

        # Process billing event message
        # @param msg [String] JSON-encoded message
        # @param delivery_info [Bunny::DeliveryInfo] AMQP delivery info
        # @param metadata [Bunny::MessageProperties] AMQP message properties
        def work_with_params(msg, delivery_info, metadata)
          store_envelope(delivery_info, metadata)

          data = parse_message(msg)
          return unless data # parse_message handles reject on error

          # Handle ping test messages (from: bin/ots queue ping)
          if data[:event_type] == 'ping.test'
            log_info 'Received ping test', event_type: data[:event_type], event_id: data[:event_id]
            return ack!
          end

          # Atomic idempotency claim: only one worker can claim a message
          unless claim_for_processing(message_id)
            log_info "Skipping duplicate message: #{message_id}"
            return ack!
          end

          log_debug "Processing billing event: #{data[:event_type]} (metadata: #{message_metadata})"

          # Reconstruct Stripe event from raw payload
          event = reconstruct_stripe_event(data)
          return reject! unless event

          # Delegate to operation with retry logic
          result = nil
          with_retry(max_retries: 3, base_delay: 2.0) do
            result = process_event(event, data)
          end

          # Handle circuit retry scheduling - don't mark as success if queued for retry
          if result == :queued
            log_info "Billing event queued for circuit retry: #{data[:event_type]}", event_id: data[:event_id]
          else
            # Mark event as successfully processed in tracking record
            mark_event_success(data[:event_id])
            log_info "Billing event processed: #{data[:event_type]}", event_id: data[:event_id]
          end

          ack!
        rescue StandardError => ex
          log_error 'Unexpected error processing billing event', ex

          # Mark event as failed in tracking record
          mark_event_failed(data[:event_id], ex) if data

          reject! # Send to DLQ
        end

        private

        # Reconstruct Stripe::Event from raw JSON payload
        # @param data [Hash] Parsed message data
        # @return [Stripe::Event, nil] Reconstructed event or nil on error
        def reconstruct_stripe_event(data)
          payload = data[:payload]

          unless payload
            log_error 'Missing payload in billing event message'
            return nil
          end

          parsed = JSON.parse(payload)
          Stripe::Event.construct_from(parsed)
        rescue JSON::ParserError => ex
          log_error "Invalid JSON in billing event payload: #{ex.message}"
          nil
        rescue StandardError => ex
          log_error "Failed to reconstruct Stripe event: #{ex.message}"
          nil
        end

        # Process the Stripe event via the billing operation
        # @param event [Stripe::Event] The Stripe event
        # @param data [Hash] Original message data (for context)
        def process_event(event, data)
          # Lookup the webhook event record for circuit retry scheduling
          webhook_event = Billing::StripeWebhookEvent.find_by_identifier(event.id)

          operation = Billing::Operations::ProcessWebhookEvent.new(
            event: event,
            context: {
              source: :async_worker,
              source_message_id: message_id,
              received_at: data[:received_at],
              webhook_event: webhook_event,
            },
          )
          operation.call
        end

        # Mark the Stripe webhook event as successfully processed
        # @param event_id [String] Stripe event ID
        def mark_event_success(event_id)
          return unless event_id

          event_record = Billing::StripeWebhookEvent.find_by_identifier(event_id)
          event_record&.mark_success!
        rescue StandardError => ex
          # Don't fail the job if tracking update fails
          log_error "Failed to mark event as success: #{ex.message}"
        end

        # Mark the Stripe webhook event as failed
        # @param event_id [String] Stripe event ID
        # @param error [Exception] The error that caused the failure
        def mark_event_failed(event_id, error)
          return unless event_id

          event_record = Billing::StripeWebhookEvent.find_by_identifier(event_id)
          event_record&.mark_failed!(error)
        rescue StandardError => ex
          # Don't fail the job if tracking update fails
          log_error "Failed to mark event as failed: #{ex.message}"
        end
      end
    end
  end
end
