# apps/web/billing/models/stripe_webhook_event.rb
#
# frozen_string_literal: true

module Billing
  # StripeWebhookEvent - Production-grade webhook event tracking
  #
  # Provides comprehensive tracking for Stripe webhook events including:
  # - Idempotency (prevent duplicate processing)
  # - Processing state machine (pending → success/failed/retrying)
  # - Error tracking and retry logic
  # - Full event metadata storage for debugging
  # - Event payload storage for replay capability
  #
  # ## State Machine
  #
  # Events transition through these states:
  #   pending → success                    # Happy path
  #   pending → retrying → success         # Transient failure recovery
  #   pending → retrying → failed          # Permanent failure (3 retries)
  #
  # ## Usage Example
  #
  #   # Initialize event with metadata (first time)
  #   event = StripeWebhookEvent.new(stripe_event_id: stripe_event.id)
  #   event.event_type = stripe_event.type
  #   event.api_version = stripe_event.api_version
  #   event.event_payload = raw_json_payload
  #   event.first_seen_at = Time.now.to_i.to_s
  #   event.save
  #
  #   # Start processing
  #   event.mark_processing!
  #
  #   # On success
  #   event.mark_success!
  #
  #   # On failure
  #   begin
  #     process_webhook(event)
  #     event.mark_success!
  #   rescue => error
  #     event.mark_failed!(error)
  #     # Will set status to 'retrying' if retries remain, 'failed' if exhausted
  #   end
  #
  #   # Check status
  #   event = StripeWebhookEvent.find_by_identifier(stripe_event.id)
  #   event.success?       # => true if processing succeeded
  #   event.retryable?     # => true if can retry (retry_count < 3)
  #
  class StripeWebhookEvent < Familia::Horreum
    using Familia::Refinements::TimeLiterals

    prefix :stripe_webhook_event

    feature :expiration
    default_expiration 30.days # Extended for compliance/audit

    identifier_field :stripe_event_id

    # ========================================
    # Core Identification
    # ========================================
    field :stripe_event_id  # Stripe event ID (evt_xxx)
    field :event_type       # Event type (e.g., customer.subscription.updated)
    field :api_version      # Stripe API version (e.g., "2023-10-16")
    field :livemode         # Boolean: true for live, false for test

    # ========================================
    # Processing State Machine
    # ========================================
    # States: pending → success | failed | retrying → success | failed
    field :processing_status # pending|success|failed|retrying
    field :processed_at      # Timestamp when successfully processed
    field :first_seen_at     # Timestamp when first received
    field :last_attempt_at   # Timestamp of most recent processing attempt
    field :retry_count       # Number of processing attempts (default: 0)
    field :error_message     # Error details if processing failed

    # ========================================
    # Stripe Event Metadata
    # ========================================
    field :created           # Stripe's event creation timestamp (Unix)
    field :request_id        # Stripe request ID (req_xxx) - nullable
    field :data_object_id    # ID of affected resource (cus_xxx, sub_xxx, etc.)
    field :pending_webhooks  # Number of pending webhooks for this event

    # ========================================
    # Debugging and Replay
    # ========================================
    field :event_payload     # Full JSON payload from Stripe

    # Check if event was already processed successfully
    #
    # @param stripe_event_id [String] Stripe event ID
    # @return [Boolean] True if event was processed successfully
    def self.processed?(stripe_event_id)
      event = find_by_identifier(stripe_event_id)
      return false unless event

      event.success?
    end


    # ========================================
    # State Checking Methods
    # ========================================

    # Check if event processing succeeded
    # @return [Boolean] True if status is 'success'
    def success?
      processing_status == 'success'
    end

    # Check if event processing failed permanently
    # @return [Boolean] True if status is 'failed'
    def failed?
      processing_status == 'failed'
    end

    # Check if event is pending processing
    # @return [Boolean] True if status is 'pending'
    def pending?
      processing_status == 'pending'
    end

    # Check if event is in retry state
    # @return [Boolean] True if status is 'retrying'
    def retrying?
      processing_status == 'retrying'
    end

    # ========================================
    # Retry Logic Methods
    # ========================================

    # Check if event can be retried
    # @return [Boolean] True if retry_count < 3 and not already successful
    def retryable?
      retry_count.to_i < 3 && !success?
    end

    # Check if max retries have been reached
    # @return [Boolean] True if retry_count >= 3
    def max_retries_reached?
      retry_count.to_i >= 3
    end

    # ========================================
    # State Transition Methods
    # ========================================

    # Mark event as currently being processed
    # Increments retry count and updates timestamp
    # @return [Boolean] True if save succeeded
    def mark_processing!
      self.processing_status = 'pending'
      self.last_attempt_at   = Time.now.to_i.to_s
      self.retry_count       = (retry_count.to_i + 1).to_s
      save
    end

    # Mark event as successfully processed
    # Clears any previous errors
    # @return [Boolean] True if save succeeded
    def mark_success!
      self.processing_status = 'success'
      self.processed_at      = Time.now.to_i.to_s
      self.error_message     = nil # Clear any previous errors
      save
    end

    # Mark event as failed
    # Sets status to 'retrying' if retries remain, 'failed' if exhausted
    # @param error [Exception] The error that caused the failure
    # @return [Boolean] True if save succeeded
    def mark_failed!(error)
      self.processing_status = max_retries_reached? ? 'failed' : 'retrying'
      self.error_message     = error.message
      self.last_attempt_at   = Time.now.to_i.to_s
      save
    end

    # ========================================
    # Debugging Methods
    # ========================================

    # Deserialize the stored event payload
    # @return [Hash, nil] Parsed JSON or nil if payload missing/invalid
    def deserialize_payload
      return nil unless event_payload

      JSON.parse(event_payload)
    rescue JSON::ParserError
      nil
    end

    # Reconstruct Stripe event from stored payload
    # @return [Stripe::Event, nil] Stripe event object or nil if payload missing/invalid
    def stripe_event
      return nil unless event_payload

      Stripe::Event.construct_from(deserialize_payload)
    end
  end
end
