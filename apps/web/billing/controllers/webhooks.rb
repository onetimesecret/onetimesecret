# apps/web/billing/controllers/webhooks.rb
#
# frozen_string_literal: true

require_relative 'base'
require_relative '../lib/webhook_validator'
require_relative '../operations/process_webhook_event'
require 'stripe'

module Billing
  module Controllers
    class Webhooks
      include Controllers::Base

      # Handle Stripe webhook events
      #
      # Processes subscription lifecycle events and product/price updates.
      # Uses WebhookValidator for comprehensive security validation:
      # - Signature verification
      # - Timestamp validation (replay attack prevention)
      # - Atomic duplicate detection
      #
      # POST /billing/webhook
      #
      # @return [HTTP 200] Success response
      # @return [HTTP 400] Invalid payload, signature, or timestamp
      # @return [HTTP 500] Processing failure (Stripe will retry)
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

        # Check if event was already successfully processed (idempotency)
        if Billing::StripeWebhookEvent.processed?(event.id)
          billing_logger.info 'Webhook event already processed successfully (duplicate)', {
            event_type: event.type,
            event_id: event.id,
          }
          res.status = 200
          return json_success('Event already processed')
        end

        # Initialize event record with full Stripe metadata
        event_record = validator.initialize_event_record(event, payload)

        # Check if max retries reached (permanent failure)
        if event_record.max_retries_reached?
          billing_logger.error 'Webhook event max retries reached - giving up', {
            event_type: event.type,
            event_id: event.id,
            retry_count: event_record.retry_count,
            last_error: event_record.error_message,
          }
          res.status = 200  # Return 200 to stop Stripe retries
          return json_success('Event max retries reached')
        end

        billing_logger.info 'Webhook event received and validated', {
          event_type: event.type,
          event_id: event.id,
          retry_count: event_record.retry_count,
        }

        # Mark event as currently processing
        event_record.mark_processing!

        # Process event with error handling and state tracking
        begin
          Billing::Operations::ProcessWebhookEvent.new(event: event).call

          # Mark as successfully processed
          event_record.mark_success!

          billing_logger.info 'Webhook event processed successfully', {
            event_type: event.type,
            event_id: event.id,
            retry_count: event_record.retry_count,
          }

          res.status = 200
          json_success('Event processed')
        rescue StandardError => ex
          # Mark as failed (will set to 'retrying' if retries remain, 'failed' if exhausted)
          event_record.mark_failed!(ex)

          billing_logger.error 'Webhook processing failed', {
            event_type: event.type,
            event_id: event.id,
            retry_count: event_record.retry_count,
            processing_status: event_record.processing_status,
            error: ex.message,
            backtrace: ex.backtrace&.first(5),
          }

          # Return 500 so Stripe retries (if retries remain)
          # Return 200 if max retries reached (to stop Stripe retries)
          if event_record.max_retries_reached?
            res.status = 200
            json_error('Event max retries reached', status: 200)
          else
            res.status = 500
            json_error('Webhook processing failed', status: 500)
          end
        end
      end

      # Event processing logic is in Billing::Operations::ProcessWebhookEvent
      # This keeps the controller focused on HTTP handling and state management
    end
  end
end
