# apps/web/billing/lib/webhook_validator.rb
#
# frozen_string_literal: true

require 'stripe'

module Billing
  # WebhookValidator - Security-focused webhook validation
  #
  # Provides comprehensive validation for Stripe webhook events:
  # - Signature verification to ensure authenticity
  # - Timestamp validation to prevent replay attacks
  # - Duplicate event detection
  # - Structured logging for security auditing
  #
  # ## Security Features
  #
  # 1. **Signature Verification**: Uses webhook signing secret to verify
  #    that events actually came from Stripe
  #
  # 2. **Timestamp Validation**: Rejects events older than 5 minutes to
  #    prevent replay attacks
  #
  # 3. **Duplicate Detection**: Uses atomic Redis operations to prevent
  #    processing the same event multiple times
  #
  # ## Usage
  #
  #   validator = Billing::WebhookValidator.new
  #
  #   # In webhook controller
  #   event = validator.construct_event(payload, signature)
  #
  #   if validator.already_processed?(event.id)
  #     return 200  # Already handled
  #   end
  #
  #   # Process event...
  #
  #   validator.mark_processed!(event.id, event.type)
  #
  class WebhookValidator
    include Onetime::LoggerMethods

    # Maximum age for webhook events (5 minutes)
    # Events older than this are rejected to prevent replay attacks
    MAX_EVENT_AGE = 300 # seconds

    # Maximum future timestamp tolerance (1 minute)
    # Events with timestamps more than 1 minute in the future are rejected
    # This accounts for minor clock drift between Stripe and our servers
    MAX_FUTURE_TOLERANCE = 60 # seconds

    def initialize(webhook_secret: nil)
      @webhook_secret = webhook_secret || Onetime.billing_config.webhook_signing_secret

      unless @webhook_secret
        raise ArgumentError, 'Webhook signing secret not configured'
      end
    end

    # Construct and validate webhook event
    #
    # Performs three critical validations:
    # 1. Verifies Stripe signature
    # 2. Validates event timestamp freshness
    # 3. Parses JSON payload
    #
    # @param payload [String] Raw request body
    # @param signature [String] Stripe-Signature header value
    # @return [Stripe::Event] Validated Stripe event
    # @raise [JSON::ParserError] If payload is invalid JSON
    # @raise [Stripe::SignatureVerificationError] If signature is invalid
    # @raise [SecurityError] If event timestamp is invalid
    #
    # @example
    #   begin
    #     event = validator.construct_event(request.body.read, request.env['HTTP_STRIPE_SIGNATURE'])
    #   rescue SecurityError => e
    #     return [400, {}, ['Invalid event timestamp']]
    #   end
    #
    def construct_event(payload, signature)
      billing_logger.debug '[WebhookValidator] Validating webhook event'

      # Verify signature and construct event
      begin
        event = Stripe::Webhook.construct_event(payload, signature, @webhook_secret)
      rescue JSON::ParserError => ex
        billing_logger.error '[WebhookValidator] Invalid JSON payload', {
          error: ex.message,
        }
        raise
      rescue Stripe::SignatureVerificationError => ex
        billing_logger.error '[WebhookValidator] Invalid signature', {
          error: ex.message,
        }
        raise
      end

      # Validate event timestamp to prevent replay attacks
      verify_timestamp!(event)

      billing_logger.info '[WebhookValidator] Event validated successfully', {
        event_id: event.id,
        event_type: event.type,
        created_at: Time.at(event.created).iso8601,
      }

      event
    end

    # Check if event was already processed
    #
    # Uses atomic Redis operation to check for duplicate events.
    # This is non-blocking and safe for concurrent webhook deliveries.
    #
    # @param event_id [String] Stripe event ID
    # @return [Boolean] True if event was already processed
    #
    def already_processed?(event_id)
      Billing::ProcessedWebhookEvent.processed?(event_id)
    end

    # Mark event as processed (atomic operation)
    #
    # Uses Redis SETNX for atomic check-and-set to prevent race conditions.
    # Returns true if successfully marked (was new), false if already processed.
    #
    # @param event_id [String] Stripe event ID
    # @param event_type [String] Event type (e.g., 'customer.subscription.updated')
    # @return [Boolean] True if marked successfully, false if already existed
    #
    def mark_processed!(event_id, event_type)
      result = Billing::ProcessedWebhookEvent.mark_processed_if_new!(event_id, event_type)

      if result
        billing_logger.debug '[WebhookValidator] Event marked as processed', {
          event_id: event_id,
          event_type: event_type,
        }
      else
        billing_logger.info '[WebhookValidator] Event already processed', {
          event_id: event_id,
          event_type: event_type,
        }
      end

      result
    end

    # Initialize event record with full Stripe metadata
    #
    # Stores all event details for debugging, replay, and compliance.
    # Only initializes if this is the first time we've seen this event.
    #
    # @param stripe_event [Stripe::Event] Stripe event object
    # @param payload [String] Raw JSON payload from webhook
    # @return [Billing::ProcessedWebhookEvent] Event record
    #
    def initialize_event_record(stripe_event, payload)
      event = Billing::ProcessedWebhookEvent.new(stripe_event_id: stripe_event.id).load!

      # Only initialize if this is a new event
      return event if event.first_seen_at

      event.stripe_event_id = stripe_event.id
      event.event_type = stripe_event.type
      event.api_version = stripe_event.api_version
      event.livemode = stripe_event.livemode.to_s
      event.created = stripe_event.created.to_s
      event.request_id = stripe_event.request&.id
      event.data_object_id = stripe_event.data.object.id
      event.pending_webhooks = stripe_event.pending_webhooks.to_s
      event.event_payload = payload
      event.first_seen_at = Time.now.to_i.to_s
      event.retry_count = '0'

      event.dbclient.set(event.dbkey, event.to_json)
      event.dbclient.expire(event.dbkey, 30 * 24 * 60 * 60)

      billing_logger.debug '[WebhookValidator] Event metadata initialized', {
        event_id: stripe_event.id,
        event_type: stripe_event.type,
        api_version: stripe_event.api_version,
        livemode: stripe_event.livemode,
      }

      event
    end

    # Check if event was successfully processed
    #
    # @param event_id [String] Stripe event ID
    # @return [Boolean] True if event processed successfully
    #
    def successfully_processed?(event_id)
      event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id).load!
      event.success?
    end

    # Remove processed marker (for rollback on failure)
    #
    # Used when event processing fails and we want Stripe to retry.
    # This ensures eventual consistency.
    #
    # @param event_id [String] Stripe event ID
    # @return [void]
    #
    def unmark_processed!(event_id)
      event = Billing::ProcessedWebhookEvent.new(stripe_event_id: event_id)
      return unless event.exists?

      event.destroy!
      billing_logger.info '[WebhookValidator] Event unmarked for retry', {
        event_id: event_id,
      }
    end

    private

    # Verify event timestamp to prevent replay attacks
    #
    # Rejects events that are:
    # - Older than MAX_EVENT_AGE (5 minutes)
    # - More than MAX_FUTURE_TOLERANCE (1 minute) in the future
    #
    # @param event [Stripe::Event] Stripe event
    # @raise [SecurityError] If timestamp is invalid
    #
    def verify_timestamp!(event)
      event_time   = Time.at(event.created)
      current_time = Time.now
      age          = current_time - event_time

      # Check if event is too old (replay attack)
      if age > MAX_EVENT_AGE
        billing_logger.error '[WebhookValidator] Event too old (possible replay attack)', {
          event_id: event.id,
          event_type: event.type,
          event_time: event_time.iso8601,
          current_time: current_time.iso8601,
          age_seconds: age.to_i,
        }

        raise SecurityError, "Event too old: #{age.to_i}s (max: #{MAX_EVENT_AGE}s)"
      end

      # Check if event is too far in the future (clock skew or manipulation)
      if age < -MAX_FUTURE_TOLERANCE
        billing_logger.error '[WebhookValidator] Event timestamp in future', {
          event_id: event.id,
          event_type: event.type,
          event_time: event_time.iso8601,
          current_time: current_time.iso8601,
          future_seconds: age.abs.to_i,
        }

        raise SecurityError, "Event timestamp in future: #{age.abs.to_i}s"
      end

      billing_logger.debug '[WebhookValidator] Timestamp valid', {
        event_id: event.id,
        age_seconds: age.to_i,
      }
    end
  end
end
