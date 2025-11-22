# frozen_string_literal: true

module Billing
  # ProcessedWebhookEvent - Deduplication for Stripe webhook events
  #
  # Tracks processed webhook events to prevent duplicate processing.
  # Stripe may send duplicate events during retries or outages.
  #
  # Uses atomic Redis operations to prevent race conditions between
  # concurrent webhook deliveries.
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
    #
    # @param stripe_event_id [String] Stripe event ID
    # @return [Boolean] True if event was already processed
    def self.processed?(stripe_event_id)
      event = new(stripe_event_id: stripe_event_id)
      # Use dbclient.exists to check key existence
      # FakeRedis returns boolean, real Redis returns integer
      result = event.dbclient.exists?(event.dbkey)
      result == 1 || result == true
    end

    # Mark event as processed (non-atomic, use mark_processed_if_new! instead)
    #
    # @param stripe_event_id [String] Stripe event ID
    # @param event_type [String] Event type
    # @return [ProcessedWebhookEvent] Saved event record
    def self.mark_processed!(stripe_event_id, event_type)
      event = new(stripe_event_id: stripe_event_id)
      event.event_type = event_type
      event.processed_at = Time.now.to_i.to_s

      # Store as JSON string, same as atomic version
      event.dbclient.set(event.dbkey, event.to_json)

      # Set expiration
      ttl_seconds = 7 * 24 * 60 * 60  # 7 days
      event.dbclient.expire(event.dbkey, ttl_seconds)

      event
    end

    # Check if this event instance exists in Redis
    def exists?
      result = dbclient.exists?(dbkey)
      result == 1 || result == true
    end

    # Delete this event from Redis
    def destroy!
      dbclient.del(dbkey)
    end

    # Atomically mark event as processed if not already processed
    #
    # This method uses Redis SETNX operation to prevent race conditions
    # when processing concurrent webhook deliveries.
    #
    # @param stripe_event_id [String] Stripe event ID
    # @param event_type [String] Event type
    # @return [Boolean] True if marked successfully (was new), false if already processed
    def self.mark_processed_if_new!(stripe_event_id, event_type)
      event = new(stripe_event_id: stripe_event_id)
      event.event_type = event_type
      event.processed_at = Time.now.to_i.to_s

      # Try to save with NX flag (only if not exists)
      # Returns true if key was set, false if key already existed
      # Familia v2: use dbclient for redis connection, dbkey for the key
      result = event.dbclient.setnx(event.dbkey, event.to_json)

      # Set expiration if we successfully created the key
      if result
        ttl_seconds = 7 * 24 * 60 * 60  # 7 days
        event.dbclient.expire(event.dbkey, ttl_seconds)
      end

      result
    end
  end
end
