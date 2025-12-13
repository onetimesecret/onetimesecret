# apps/web/billing/controllers/webhooks.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../lib/webhook_validator'
require 'stripe'

module Billing
  module Controllers
    class Webhooks
      include Controllers::Base

      # Handle Stripe webhook events
      #
      # Validates webhook signature and enqueues for async processing.
      # This allows Puma to return quickly, eliminating data loss risk.
      #
      # Uses WebhookValidator for comprehensive security validation:
      # - Signature verification
      # - Timestamp validation (replay attack prevention)
      # - Atomic duplicate detection
      #
      # POST /billing/webhook
      #
      # @return [HTTP 200] Event queued for processing
      # @return [HTTP 400] Invalid payload, signature, or timestamp
      # @return [HTTP 500] Queue unavailable (Stripe will retry)
      #
      def handle_event
        payload    = req.body.read
        sig_header = req.env['HTTP_STRIPE_SIGNATURE']

        unless sig_header
          billing_logger.warn 'Webhook received without signature header'
          res.status = 400
          return json_error('Missing signature header', status: 400)
        end

        # Initialize webhook validator with security features
        begin
          validator = Billing::WebhookValidator.new
        rescue StandardError => ex
          billing_logger.error 'Webhook validator initialization failed', {
            exception: ex,
            message: ex.message,
          }
          res.status = 500
          return json_error('Webhook configuration error', status: 500)
        end

        # Construct and validate event (signature + timestamp + replay protection)
        begin
          event = validator.construct_event(payload, sig_header)
        rescue JSON::ParserError => ex
          billing_logger.error 'Invalid webhook payload', {
            exception: ex,
          }
          res.status = 400
          return json_error('Invalid payload', status: 400)
        rescue Stripe::SignatureVerificationError => ex
          billing_logger.error 'Invalid webhook signature', {
            exception: ex,
          }
          res.status = 400
          return json_error('Invalid signature', status: 400)
        rescue SecurityError => ex
          # Timestamp validation failed (replay attack or clock skew)
          billing_logger.error 'Webhook timestamp validation failed', {
            exception: ex,
            message: ex.message,
          }
          res.status = 400
          return json_error('Invalid event timestamp', status: 400)
        end

        # Check if event was already processed or is being processed (idempotency)
        existing_event = Billing::StripeWebhookEvent.find_by_identifier(event.id)
        if existing_event
          if existing_event.success?
            billing_logger.info 'Webhook event already processed successfully (duplicate)', {
              event_type: event.type,
              event_id: event.id,
            }
            res.status = 200
            return json_success('Event already processed')
          elsif existing_event.pending? || existing_event.retrying?
            billing_logger.info 'Webhook event already queued for processing (duplicate)', {
              event_type: event.type,
              event_id: event.id,
              status: existing_event.processing_status,
            }
            res.status = 200
            return json_success('Event already queued')
          elsif existing_event.max_retries_reached?
            # Event failed permanently after multiple attempts - stop Stripe retries
            billing_logger.error 'Webhook event max retries reached - giving up', {
              event_type: event.type,
              event_id: event.id,
              retry_count: existing_event.retry_count,
              last_error: existing_event.error_message,
            }
            res.status = 200  # Return 200 to stop Stripe retries
            return json_success('Event max retries reached')
          end
          # If failed but retries remain, allow re-processing by falling through
        end

        # Initialize event record for tracking (status: queued)
        event_record = existing_event || validator.initialize_event_record(event, payload)

        billing_logger.info 'Webhook event validated, enqueueing for async processing', {
          event_type: event.type,
          event_id: event.id,
        }

        # Mark event as queued and enqueue for async processing
        begin
          event_record.mark_processing!

          Onetime::Jobs::Publisher.enqueue_billing_event(event, payload)

          billing_logger.info 'Webhook event enqueued successfully', {
            event_type: event.type,
            event_id: event.id,
          }

          res.status = 200
          json_success('Event queued')
        rescue StandardError => ex
          # Enqueue failed (RabbitMQ unavailable) - return 500 so Stripe retries
          begin
            event_record.mark_failed!(ex)
          rescue StandardError => marking_error
            billing_logger.error 'Failed to mark event as failed', {
              original_error: ex.message,
              marking_error: marking_error.message,
              event_id: event.id,
            }
          end

          billing_logger.error 'Failed to enqueue webhook event', {
            event_type: event.type,
            event_id: event.id,
            error: ex.message,
            backtrace: ex.backtrace&.first(5),
          }

          res.status = 500
          json_error('Queue unavailable', status: 500)
        end
      end

      # Event processing logic is in BillingWorker -> ProcessWebhookEvent
      # This controller focuses on validation and enqueueing
    end
  end
end
