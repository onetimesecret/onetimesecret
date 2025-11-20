# frozen_string_literal: true

module Billing
  module Models
    # ProcessedWebhookEvent - Deduplication for Stripe webhook events
    #
    # Tracks processed webhook events to prevent duplicate processing.
    # Stripe may send duplicate events during retries or outages.
    #
    class ProcessedWebhookEvent < Familia::Horreum
      using Familia::Refinements::TimeLiterals

      prefix :billing_webhook_event

      feature :expiration
      default_expiration 7.days # Keep for 7 days then auto-expire

      identifier_field :stripe_event_id

      field :stripe_event_id  # Stripe event ID (evt_xxx)
      field :event_type       # Event type (e.g., product.updated)
      field :processed_at     # Timestamp when processed

      # Check if event was already processed
      def self.processed?(stripe_event_id)
        load(stripe_event_id)&.exists?
      end

      # Mark event as processed
      def self.mark_processed!(stripe_event_id, event_type)
        event = new(stripe_event_id: stripe_event_id)
        event.event_type = event_type
        event.processed_at = Time.now.to_i.to_s
        event.save
      end
    end
  end
end
