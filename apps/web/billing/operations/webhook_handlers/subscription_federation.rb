# apps/web/billing/operations/webhook_handlers/subscription_federation.rb
#
# frozen_string_literal: true

require 'onetime/utils/email_hash'
require_relative '../../models/pending_federated_subscription'

module Billing
  module Operations
    module WebhookHandlers
      # SubscriptionFederation - Mixin for cross-region subscription federation
      #
      # Provides two-path matching for webhook handlers:
      #
      # Path 1 (Owner): Match by stripe_customer_id
      #   - Organization has direct link to Stripe customer
      #   - Authoritative source, always updated
      #
      # Path 2 (Federated): Match by email_hash
      #   - Organization has matching hash but no stripe_customer_id
      #   - Receives subscription benefits passively
      #   - Marked with subscription_federated_at for UX notification
      #
      # Security: Uses immutable email_hash from Stripe customer metadata.
      # The hash is set at subscription creation and never updated, preventing
      # email-swap attacks where an attacker changes their Stripe email to a
      # victim's email.
      #
      # @see https://github.com/onetimesecret/onetimesecret/issues/2471
      #
      module SubscriptionFederation
        private

        # Path 1: Find owner organization by direct stripe_customer_id link
        #
        # @param stripe_customer_id [String] Stripe customer ID
        # @return [Onetime::Organization, nil] Owner organization or nil
        #
        def find_owner_org(stripe_customer_id)
          return nil if stripe_customer_id.to_s.empty?

          Onetime::Organization.find_by_stripe_customer_id(stripe_customer_id)
        end

        # Path 2: Find organizations with matching email_hash that don't own a subscription
        #
        # These are "federated" orgs - they have the same billing email as the
        # subscription owner in a different region, but don't have a direct
        # Stripe customer link.
        #
        # @param email_hash [String] HMAC hash of email from Stripe metadata
        # @param exclude_org [Onetime::Organization, nil] Organization to exclude (typically owner)
        # @return [Array<Onetime::Organization>] Non-owner orgs with matching hash
        #
        def find_federated_orgs(email_hash, exclude_org: nil)
          return [] if email_hash.to_s.empty?

          # Use the dedicated finder that only returns non-owner orgs
          orgs = Onetime::Organization.find_federated_by_email_hash(email_hash)
          return [] unless orgs.is_a?(Array)

          # Exclude the specified org if provided (typically the owner, but should
          # already be filtered out by find_federated_by_email_hash)
          if exclude_org
            orgs.reject { |org| org.objid == exclude_org.objid }
          else
            orgs
          end
        end

        # Get immutable email_hash from Stripe customer metadata
        #
        # CRITICAL: This hash is set at subscription creation and must NEVER be
        # updated in Stripe, even if the customer's email changes. This immutability
        # is the primary defense against email-swap attacks.
        #
        # @param stripe_customer [Stripe::Customer] Stripe customer object
        # @return [String, nil] Email hash from metadata, or nil if not set
        #
        def get_stripe_email_hash(stripe_customer)
          return nil unless stripe_customer

          stripe_customer.metadata['email_hash']
        end

        # Compute email hash from Stripe customer's current email
        #
        # Used as a fallback when email_hash metadata is not set (legacy customers).
        # For new customers, always prefer get_stripe_email_hash which uses the
        # immutable metadata value.
        #
        # @param stripe_customer [Stripe::Customer] Stripe customer object
        # @return [String, nil] Computed email hash, or nil if email is empty
        #
        def compute_email_hash_from_stripe(stripe_customer)
          return nil unless stripe_customer
          return nil if stripe_customer.email.to_s.empty?

          Onetime::Utils::EmailHash.compute(stripe_customer.email)
        end

        # Update federated organization with subscription data
        #
        # IMPORTANT: Federated orgs do NOT get stripe_customer_id or stripe_subscription_id.
        # They only receive subscription status/plan fields. The absence of stripe_customer_id
        # is what distinguishes federated orgs from owners.
        #
        # Marks the organization as federated (if first time) and updates
        # subscription status fields from the Stripe subscription.
        #
        # @param org [Onetime::Organization] Organization to update
        # @param subscription [Stripe::Subscription] Stripe subscription
        # @return [Boolean] True if this was the first federation (for notification)
        #
        def update_federated_org(org, subscription)
          first_federation = !org.subscription_federated?

          # Update ONLY status fields - NOT stripe_customer_id or stripe_subscription_id
          # Federated orgs don't own the subscription, they just receive benefits
          org.subscription_status     = subscription.status
          period_end                  = subscription.items.data.first&.current_period_end
          org.subscription_period_end = period_end.to_s if period_end

          # Extract plan ID using the same logic as update_from_stripe_subscription
          price    = subscription.items.data.first&.price
          price_id = price&.id
          if price_id
            plan_id    = Billing::PlanValidator.resolve_plan_id(price_id)
            org.planid = plan_id if plan_id
          end

          # Mark as federated if first time
          org.mark_subscription_federated! if first_federation

          org.save

          first_federation
        end

        # Process subscription event with two-path matching
        #
        # Convenience method that implements the common pattern for subscription
        # handlers: find owner, update owner, then find and update federated orgs.
        #
        # @param subscription [Stripe::Subscription] Stripe subscription object
        # @yield [org, is_owner] Block called for each matching org
        # @yieldparam org [Onetime::Organization] Matching organization
        # @yieldparam is_owner [Boolean] True if this is the owner org
        # @return [Symbol] :success, :owner_only, :federated_only, or :not_found
        #
        def process_with_federation(subscription)
          stripe_customer_id = subscription.customer
          stripe_customer    = Stripe::Customer.retrieve(stripe_customer_id)

          # Get email hash - prefer metadata (immutable), fall back to computed
          email_hash   = get_stripe_email_hash(stripe_customer)
          email_hash ||= compute_email_hash_from_stripe(stripe_customer)

          found_any = false

          # Path 1: Owner (direct link)
          owner_org = find_owner_org(stripe_customer_id)
          if owner_org
            found_any = true
            yield owner_org, true if block_given?
          end

          # Path 2: Federated orgs (matching hash, no direct link)
          federated = find_federated_orgs(email_hash, exclude_org: owner_org)
          federated.each do |org|
            found_any = true
            yield org, false if block_given?
          end

          unless found_any
            # No account exists yet - store for future matching
            store_pending_federation(email_hash, subscription, stripe_customer)
            return :pending_stored
          end

          return :owner_only if owner_org && federated.empty?
          return :federated_only if owner_org.nil? && federated.any?

          :success
        end

        # Store subscription data for future account creation matching
        #
        # When a webhook fires but no account exists in this region, we store
        # the subscription state (NOT PII) keyed by email_hash. When the user
        # later creates an account and verifies their email, we match by hash
        # and apply the benefits.
        #
        # @param email_hash [String] HMAC hash from Stripe customer metadata
        # @param subscription [Stripe::Subscription] Stripe subscription
        # @param stripe_customer [Stripe::Customer] Stripe customer (for region)
        # @return [Billing::PendingFederatedSubscription, nil]
        #
        def store_pending_federation(email_hash, subscription, stripe_customer)
          return nil if email_hash.to_s.empty?

          home_region = stripe_customer&.metadata&.[]('home_region')

          Billing::PendingFederatedSubscription.store_from_webhook(
            email_hash: email_hash,
            subscription: subscription,
            home_region: home_region,
          )
        end
      end
    end
  end
end
