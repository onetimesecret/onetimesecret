# frozen_string_literal: true

require 'stripe'

module Billing
  # Webhook Event Validator
  #
  # Validates Stripe webhook events for:
  # - Signature authenticity
  # - Timestamp freshness (replay attack protection)
  # - Duplicate event detection
  #
  # ## Usage
  #
  #   validator = Billing::WebhookValidator.new
  #   event = validator.construct_event(payload, sig_header)
  #
  #   if validator.already_processed?(event.id)
  #     # Skip duplicate
  #   end
  #
  class WebhookValidator
    include Onetime::LoggerMethods

    # Maximum age for webhook events (5 minutes)
    # Events older than this are rejected to prevent replay attacks
    MAX_EVENT_AGE = 300

    # @return [String] Webhook signing secret
    attr_reader :webhook_secret

    def initialize
      @webhook_secret = Onetime.billing_config.webhook_signing_secret

      unless @webhook_secret
        raise ArgumentError, 'Webhook signing secret not configured'
      end
    end

    # Construct and validate webhook event
    #
    # Verifies signature and timestamp before returning event.
    #
    # @param payload [String] Raw request body
    # @param sig_header [String] Stripe-Signature header value
    # @return [Stripe::Event] Validated event
    # @raise [Stripe::SignatureVerificationError] If signature invalid
    # @raise [SecurityError] If event too old
    def construct_event(payload, sig_header)
      # Verify signature
      event = Stripe::Webhook.construct_event(
        payload,
        sig_header,
        webhook_secret
      )

      # Verify timestamp to prevent replay attacks
      verify_timestamp!(event)

      event
    rescue JSON::ParserError => ex
      billing_logger.error 'Webhook payload is not valid JSON', {
        exception: ex,
      }
      raise
    rescue Stripe::SignatureVerificationError => ex
      billing_logger.error 'Webhook signature verification failed', {
        exception: ex,
      }
      raise
    end

    # Check if event was already processed
    #
    # @param event_id [String] Stripe event ID
    # @return [Boolean] True if already processed
    def already_processed?(event_id)
      Billing::ProcessedWebhookEvent.processed?(event_id)
    end

    # Mark event as processed
    #
    # @param event_id [String] Stripe event ID
    # @param event_type [String] Event type
    # @return [void]
    def mark_processed!(event_id, event_type)
      Billing::ProcessedWebhookEvent.mark_processed!(event_id, event_type)
    end

    private

    # Verify event timestamp is within acceptable range
    #
    # Rejects events that are too old to prevent replay attacks.
    #
    # @param event [Stripe::Event] Event to verify
    # @raise [SecurityError] If event too old
    def verify_timestamp!(event)
      event_time = Time.at(event.created)
      age = Time.now - event_time

      if age > MAX_EVENT_AGE
        billing_logger.warn 'Webhook event too old, rejecting', {
          event_id: event.id,
          event_type: event.type,
          event_time: event_time,
          age_seconds: age.round,
          max_age: MAX_EVENT_AGE,
        }

        raise SecurityError, "Webhook event too old (#{age.round}s > #{MAX_EVENT_AGE}s)"
      end

      billing_logger.debug 'Webhook timestamp verified', {
        event_id: event.id,
        age_seconds: age.round,
      }
    end
  end
end
