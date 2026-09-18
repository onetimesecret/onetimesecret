# apps/web/billing/models/pending_federated_subscription.rb
#
# frozen_string_literal: true

require_relative '../metadata'
require_relative '../lib/plan_validator'
require_relative '../lib/plan_resolver'

module Billing
  # PendingFederatedSubscription - Temporary storage for federation webhooks
  #
  # When a Stripe subscription webhook fires but no account exists in this
  # region yet, we store the subscription state (NOT PII) keyed by email_hash.
  # Later, when the user creates an account and verifies their email, we
  # match by hash and apply the subscription benefits.
  #
  # ## Privacy Design
  #
  # This model stores NO personally identifiable information:
  # - email_hash is one-way (cannot recover email)
  # - No Stripe customer ID (fetched fresh at claim time)
  # - No email addresses or names
  #
  # The audit trail is created at account creation time, when there's an
  # actual entity to audit and the user has verified email ownership.
  #
  # ## Lifecycle
  #
  # 1. Webhook fires → no matching org → store pending record
  # 2. User creates account → email verified → compute org email_hash
  # 3. Match pending record → apply benefits → destroy pending record
  #
  # ## TTL
  #
  # Records expire after 90 days. If user doesn't create account within
  # that window, they'll be synced on the next subscription webhook
  # (e.g., monthly renewal) after account creation.
  #
  class PendingFederatedSubscription < Familia::Horreum
    using Familia::Refinements::TimeLiterals

    prefix :pending_fed_sub

    feature :expiration
    default_expiration 90.days

    # Use email_hash as identifier - overwrites on duplicate (idempotent)
    identifier_field :email_hash

    # ========================================
    # Read Index (admin visibility)
    # ========================================
    # Score: received_at epoch seconds. Member: email_hash.
    #
    # Written by .store_from_webhook after each save (subsequent notifications
    # for the same email_hash refresh the score — newest wins). Trimmed to
    # INDEX_MAX_ENTRIES on every write. Read by
    # Onetime::Operations::Billing::WebhookVisibility instead of scanning
    # object keys.
    #
    # The index is a rebuildable read cache; the pending rows remain the code
    # of record. On deploy the index is empty and populates as webhooks arrive.
    #
    # TEST-FIXTURE WARNING
    # Bare +PendingFederatedSubscription.new(...).save+ in test fixtures DOES
    # NOT populate this index. Only the production write paths do: the sole
    # writer is +Billing::PendingFederatedSubscription.record_recent_index+,
    # called by +Billing::PendingFederatedSubscription.store_from_webhook+
    # after each save. Specs that exercise admin-visibility read paths (e.g.
    # WebhookVisibility) must call +record_recent_index+ explicitly or drive
    # the flow through +store_from_webhook+, or their assertions will pass
    # vacuously against an empty sorted set.
    class_sorted_set :recent_records

    # Retention cap on the read index. Bounds Redis memory; older hashes are
    # trimmed on every write.
    INDEX_MAX_ENTRIES = 10_000

    # ========================================
    # Lookup Key (NOT PII)
    # ========================================
    # Note: identifier_field :email_hash provides uniqueness via the identifier
    # pattern. No separate index needed - find_by_identifier handles lookups.
    field :email_hash

    # ========================================
    # Subscription State (NOT PII)
    # ========================================
    field :subscription_status      # active, past_due, canceled, etc.
    field :planid                   # Plan identifier for benefit level
    field :subscription_period_end  # Unix epoch seconds as an Integer (legacy rows may hold a String)

    # ========================================
    # Metadata (NOT PII)
    # ========================================
    field :region                   # Region that owns the subscription
    field :received_at              # When webhook was first received
    field :source_stripe_event_id   # Stripe webhook event that wrote this record

    # Find pending subscription by email hash
    #
    # @param email_hash [String] HMAC hash of normalized email
    # @return [PendingFederatedSubscription, nil]
    def self.find_by_email_hash(email_hash)
      return nil if email_hash.to_s.empty?

      find_by_identifier(email_hash)
    end

    # Check if a pending subscription exists for this hash
    #
    # @param email_hash [String] HMAC hash of normalized email
    # @return [Boolean]
    def self.pending?(email_hash)
      !find_by_email_hash(email_hash).nil?
    end

    # Store or update pending subscription from webhook data
    #
    # Uses email_hash as identifier, so duplicate webhooks overwrite
    # rather than accumulate (idempotent).
    #
    # @param email_hash [String] HMAC hash from Stripe customer metadata
    # @param subscription [Stripe::Subscription] Subscription object
    # @param region [String] Region identifier from Stripe metadata
    # @param source_stripe_event_id [String, nil] Stripe webhook event ID
    # @return [PendingFederatedSubscription]
    def self.store_from_webhook(email_hash:, subscription:, region: nil, source_stripe_event_id: nil)
      pending                         = new(email_hash)  # Sets identifier (email_hash) automatically
      pending.subscription_status     = subscription.status
      pending.planid                  = extract_plan_id(subscription)
      pending.subscription_period_end = subscription.items.data.first&.current_period_end
      pending.region                  = region
      pending.received_at             = Time.now.to_i.to_s
      pending.source_stripe_event_id  = source_stripe_event_id
      pending.save
      record_recent_index(pending)
      pending
    end

    # Append this record to the admin read index and trim to cap.
    #
    # The index is a rebuildable read cache; a failure here must NOT fail the
    # webhook write path (the object row is the code of record). Log and
    # swallow.
    def self.record_recent_index(pending)
      recent_records.add(pending.email_hash, pending.received_at.to_i)
      recent_records.remrangebyrank(0, -(INDEX_MAX_ENTRIES + 1))
    rescue StandardError => ex
      Onetime.billing_logger.warn '[PendingFederatedSubscription] recent index write failed',
        exception: ex.class.name,
        message: ex.message,
        email_hash: pending.email_hash
      nil
    end

    # Drop this record's id from the admin read index.
    #
    # Called from the +destroy!+ override so any callsite that removes the
    # row (typically claim, from EnsureDefaultWorkspace) also drops the id
    # from +recent_records+. Without this the id sat at its original rank
    # until the 90-day key TTL fired, and rank-based pagination in
    # WebhookVisibility would skip one record across the page boundary each
    # time the read-side prune touched a mid-index stale id.
    #
    # Best-effort — the index is a rebuildable read cache and a failure
    # here must not fail the destroy. Log and swallow.
    def self.unindex_recent(email_hash)
      recent_records.remove(email_hash)
    rescue StandardError => ex
      Onetime.billing_logger.warn '[PendingFederatedSubscription] recent index remove failed',
        exception: ex.class.name,
        message: ex.message,
        email_hash: email_hash
      nil
    end

    # Ensure destroying a record also drops it from the admin read index.
    # Runs before +super+ so the id is gone even if the row destroy itself
    # raises (whichever the row's fate, the index should not keep it).
    def destroy!
      self.class.unindex_recent(email_hash)
      super
    end

    # Extract plan ID from subscription
    #
    # Metadata-first: pending records exist precisely for CROSS-REGION
    # subscriptions, whose price IDs are not in the local catalog by design.
    # The canonical family plan_id stamped into subscription metadata at
    # checkout is the authoritative source — the same rule as the federated
    # path in ApplySubscriptionToOrg#apply_plan_id. Catalog lookup is only a
    # fallback for subscriptions without plan_id metadata (legacy Payment
    # Links), where a local price match is still possible.
    #
    # @param subscription [Stripe::Subscription]
    # @return [String, nil]
    def self.extract_plan_id(subscription)
      plan_id = subscription.metadata&.[](Billing::Metadata::FIELD_PLAN_ID).to_s.strip

      return plan_id if !plan_id.empty? && Billing::PlanResolver.canonical_plan_id?(plan_id)

      unless plan_id.empty?
        Onetime.billing_logger.warn '[PendingFederatedSubscription] Malformed plan_id metadata, trying catalog',
          plan_id: plan_id,
          subscription_id: subscription.id
      end

      item     = subscription.items&.data&.first
      price_id = item&.price&.id.to_s.strip
      return nil if price_id.empty?

      Billing::PlanValidator.resolve_plan_id(price_id)
    rescue Billing::CatalogMissError
      # Expected for cross-region prices when metadata is absent: store the
      # pending record without a plan; the claim path skips planless records
      # and the next subscription webhook re-syncs the org directly.
      Onetime.billing_logger.warn '[PendingFederatedSubscription] No plan_id metadata and price not in local catalog',
        subscription_id: subscription.id
      nil
    end

    # Check if subscription is still active/valid
    #
    # @return [Boolean]
    def active?
      %w[active trialing past_due].include?(subscription_status)
    end

    # Check if subscription period has ended
    #
    # @return [Boolean]
    def expired?
      return false if subscription_period_end.to_s.empty?

      Time.now.to_i > subscription_period_end.to_i
    end
  end
end
