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
  # - Event payload storage for replay entitlement
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
  #   event.retryable?     # => true if can retry (attempt_count < 3)
  #
  class StripeWebhookEvent < Familia::Horreum
    using Familia::Refinements::TimeLiterals

    prefix :stripe_webhook_event

    feature :expiration
    default_expiration 5.days # Covers Stripe retry window + debugging

    identifier_field :stripe_event_id

    # ========================================
    # Read Index (admin visibility)
    # ========================================
    # Score: first_seen_at epoch seconds. Member: stripe_event_id.
    #
    # Written by WebhookValidator#initialize_event_record on first insert only,
    # and trimmed to INDEX_MAX_ENTRIES on every write. Read by
    # Onetime::Operations::Billing::WebhookVisibility instead of scanning object
    # keys, which is O(N) over the entire keyspace and yields a "recent" view
    # only by accident.
    #
    # The index is a rebuildable read cache; the object rows remain the code
    # of record. On deploy the index is empty; the 5-day TTL means it reaches
    # full population within 5 days of continuous webhook traffic. Older event
    # rows written before this index existed are absent from admin listings
    # until they are re-written or expire.
    #
    # TEST-FIXTURE WARNING
    # Bare +StripeWebhookEvent.new(...).save+ in test fixtures DOES NOT populate
    # this index. Only the production write paths do: the sole writer is
    # +Billing::StripeWebhookEvent.record_recent_index+, called by
    # +Billing::WebhookValidator#initialize_event_record+ on first insert.
    # Specs that exercise admin-visibility read paths (e.g. WebhookVisibility)
    # must call +record_recent_index+ explicitly or drive the flow through
    # +WebhookValidator+, or their assertions will pass vacuously against an
    # empty sorted set.
    class_sorted_set :recent_events

    # Retention cap on the read index. Bounds Redis memory; older ids are
    # trimmed on every write.
    INDEX_MAX_ENTRIES = 10_000

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
    field :attempt_count       # Number of webhook delivery attempts (default: 0)
    field :error_message       # Error details if processing failed
    field :processing_outcome  # Semantic result returned by ProcessWebhookEvent

    # ========================================
    # Stripe Event Metadata
    # ========================================
    field :created           # Stripe's event creation timestamp (Unix)
    field :request_id        # Stripe request ID (req_xxx) - nullable
    field :data_object_id    # ID of affected resource (cus_xxx, sub_xxx, etc.)
    field :pending_webhooks  # Number of pending webhooks for this event

    # ========================================
    # Circuit Breaker Retry Scheduling
    # ========================================
    # When the Stripe circuit breaker is open, events are scheduled for retry
    # rather than failing immediately. This allows recovery after the circuit
    # transitions to half-open or closed state.
    field :circuit_retry_at     # Unix timestamp when retry should be attempted
    field :circuit_retry_count  # Number of circuit-open retries attempted (default: 0)

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

    # Append this event to the admin read index and trim to cap.
    #
    # Called from WebhookValidator#initialize_event_record on FIRST INIT only —
    # not from #mark_processing! / #mark_success! / #save, because the index
    # score is first_seen_at (arrival time), not last-update time. Refreshing
    # the score on every state transition would break the newest-first ordering
    # the admin view depends on.
    #
    # The index is a rebuildable read cache; a failure here must NOT fail the
    # webhook write path (the object row is the code of record). Log and
    # swallow.
    def self.record_recent_index(event)
      recent_events.add(event.stripe_event_id, event.first_seen_at.to_i)
      recent_events.remrangebyrank(0, -(INDEX_MAX_ENTRIES + 1))
    rescue StandardError => ex
      Onetime.billing_logger.warn '[StripeWebhookEvent] recent index write failed',
        exception: ex.class.name,
        message: ex.message,
        event_id: event.stripe_event_id
      nil
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
    # @return [Boolean] True if attempt_count < 3 and not already successful
    def retryable?
      attempt_count.to_i < 3 && !success?
    end

    # Check if max attempts have been reached
    # @return [Boolean] True if attempt_count >= 3
    def max_attempts_reached?
      attempt_count.to_i >= 3
    end

    # ========================================
    # Circuit Breaker Retry Methods
    # ========================================

    # Maximum number of circuit-open retries before giving up
    CIRCUIT_RETRY_MAX = 5

    # Check if event is scheduled for circuit retry
    # @return [Boolean] True if circuit_retry_at is set
    def circuit_retry_scheduled?
      !circuit_retry_at.nil? && circuit_retry_at.to_i > 0
    end

    # Check if event is due for circuit retry
    # @return [Boolean] True if retry time has passed and not at max retries
    def circuit_retry_due?
      return false unless circuit_retry_scheduled?
      return false if circuit_retry_count.to_i >= CIRCUIT_RETRY_MAX

      Time.now.to_i >= circuit_retry_at.to_i
    end

    # Check if circuit retry max attempts reached
    # @return [Boolean] True if circuit_retry_count >= CIRCUIT_RETRY_MAX
    def circuit_retry_exhausted?
      circuit_retry_count.to_i >= CIRCUIT_RETRY_MAX
    end

    # Schedule event for circuit retry
    #
    # Called when the Stripe circuit breaker is open. Uses exponential
    # backoff to avoid hammering Stripe during extended outages.
    #
    # @param delay_seconds [Integer] Seconds to wait before retry (default: based on retry count)
    # @return [Boolean] True if save succeeded
    def schedule_circuit_retry(delay_seconds: nil)
      current_count = circuit_retry_count.to_i

      # Calculate delay with exponential backoff if not specified
      # Base: 60s, then 120s, 240s, 480s, 960s
      delay = delay_seconds || (60 * (2**current_count))

      self.circuit_retry_at    = (Time.now.to_i + delay).to_s
      self.circuit_retry_count = (current_count + 1).to_s
      self.processing_status   = 'retrying'
      save
    end

    # Clear circuit retry scheduling (called after successful retry)
    # @return [Boolean] True if save succeeded
    def clear_circuit_retry
      self.circuit_retry_at    = nil
      self.circuit_retry_count = '0'
      save
    end

    # Find all events due for circuit retry
    #
    # Note: This scans all webhook events. For high-volume systems, consider
    # a Redis sorted set index keyed by retry_at timestamp.
    #
    # @param limit [Integer] Maximum events to return
    # @return [Array<StripeWebhookEvent>] Events ready for retry
    def self.find_circuit_retry_due(limit: 100)
      # This is a simple implementation. For production scale, consider:
      # - A separate sorted set index: billing:webhook:circuit_retry_queue
      # - Lua script for atomic claim and processing
      due_events = []

      # Scan recent events (within last 5 days based on TTL)
      # In practice, you'd want an index for this
      Familia.dbclient.scan_each(match: 'stripe_webhook_event:*', count: 1000) do |key|
        break if due_events.size >= limit

        # Extract event ID from key (format: stripe_webhook_event:evt_xxx)
        event_id = key.split(':').last
        next if event_id.nil? || event_id.empty?

        event = find_by_identifier(event_id)
        next unless event&.circuit_retry_due?

        due_events << event
      end

      due_events
    end

    # ========================================
    # State Transition Methods
    # ========================================

    # Mark event as currently being processed
    # Increments attempt count and updates timestamp
    # @return [Boolean] True if save succeeded
    def mark_processing!
      self.processing_status  = 'pending'
      self.last_attempt_at    = Time.now.to_i.to_s
      self.attempt_count      = (attempt_count.to_i + 1).to_s
      self.processing_outcome = nil
      save
    end

    # Persist the semantic result returned by ProcessWebhookEvent.
    #
    # @param outcome [Symbol, String, nil] Semantic processing result
    # @return [Boolean] True if save succeeded
    def record_processing_outcome!(outcome)
      self.processing_outcome = outcome&.to_s
      save
    end

    # Sentinel used to distinguish "outcome kwarg omitted" from an explicit nil
    # in {mark_success!}. Omission preserves any previously-recorded outcome;
    # explicit nil clears it. This keeps future callers that forget to pass
    # `outcome:` from silently erasing a prior record.
    NO_OUTCOME_UPDATE = Object.new.freeze
    private_constant :NO_OUTCOME_UPDATE

    # Mark event as successfully processed
    # Clears any previous errors.
    #
    # @param outcome [Symbol, String, nil] Semantic processing result. When the
    #   kwarg is OMITTED, `processing_outcome` is left untouched (any prior
    #   recorded outcome is preserved). An explicit `nil` clears it — callers
    #   that want to clear the outcome must be explicit about it.
    # @return [Boolean] True if save succeeded
    def mark_success!(outcome: NO_OUTCOME_UPDATE)
      self.processing_status  = 'success'
      self.processed_at       = Time.now.to_i.to_s
      self.error_message      = nil # Clear any previous errors
      self.processing_outcome = outcome&.to_s unless outcome.equal?(NO_OUTCOME_UPDATE)
      save
    end

    # Mark event as failed
    # Sets status to 'retrying' if retries remain, 'failed' if exhausted
    # @param error [Exception] The error that caused the failure
    # @return [Boolean] True if save succeeded
    def mark_failed!(error)
      self.processing_status = max_attempts_reached? ? 'failed' : 'retrying'
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
