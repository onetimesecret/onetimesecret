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
    field :subscription_period_end  # Unix timestamp

    # ========================================
    # Metadata (NOT PII)
    # ========================================
    field :region                   # Region that owns the subscription
    field :received_at              # When webhook was first received

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
    # @return [PendingFederatedSubscription]
    def self.store_from_webhook(email_hash:, subscription:, region: nil)
      pending                         = new(email_hash)  # Sets identifier (email_hash) automatically
      pending.subscription_status     = subscription.status
      pending.planid                  = extract_plan_id(subscription)
      pending.subscription_period_end = subscription.items.data.first&.current_period_end
      pending.region                  = region
      pending.received_at             = Time.now.to_i.to_s
      pending.save
      pending
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
