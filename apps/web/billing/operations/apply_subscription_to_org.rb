# apps/web/billing/operations/apply_subscription_to_org.rb
#
# frozen_string_literal: true

require_relative '../metadata'
require_relative '../lib/plan_validator'

module Billing
  module Operations
    # ApplySubscriptionToOrg - Shared operation for writing subscription
    # state to an Organization.
    #
    # Three codepaths set billing fields on organizations:
    # 1. Webhook owner path (update_from_stripe_subscription)
    # 2. Webhook federated path (update_federated_org)
    # 3. Migration tooling (migrate_account!)
    #
    # This operation extracts the common field-setting logic so all
    # paths produce consistent state — particularly for the
    # complimentary marker and plan resolution.
    #
    # Usage:
    #   # Owner path (full update with Stripe IDs, auto-save)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: true)
    #
    #   # Federated path (no Stripe IDs, caller saves after marking federated)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: false, save: false)
    #
    #   # Migration path (owner + explicit plan when price not in catalog)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: true,
    #     planid_override: 'identity_plus_v1')
    #
    class ApplySubscriptionToOrg
      # @param org [Onetime::Organization] Organization to update
      # @param subscription [Stripe::Subscription] Stripe subscription
      # @param owner [Boolean] Whether org owns the subscription (gets Stripe IDs)
      # @param planid_override [String, nil] Explicit plan ID, skips catalog
      #   resolution. Use for migration tooling where the price may not be
      #   in the catalog yet.
      # @param save [Boolean] Whether to call org.save after applying fields.
      #   Set to false when the caller needs to set additional fields before
      #   saving (e.g., federation marking).
      # @return [Boolean, nil] Result of org.save, or nil when save: false
      def self.call(org, subscription, owner: true, planid_override: nil, save: true)
        new(org, subscription, owner: owner, planid_override: planid_override, save: save).call
      end

      def initialize(org, subscription, owner: true, planid_override: nil, save: true)
        @org              = org
        @subscription     = subscription
        @owner            = owner
        @planid_override  = planid_override
        @save             = save
      end

      def call
        apply_status_fields
        apply_plan_id
        apply_complimentary_marker
        apply_owner_fields if @owner

        @org.save if @save
      end

      private

      # Fields common to both owner and federated orgs
      def apply_status_fields
        @org.subscription_status = @subscription.status

        period_end                   = @subscription.items.data.first&.current_period_end
        @org.subscription_period_end = period_end.to_s if period_end
      end

      # Resolve plan from catalog (owner) or metadata (federated)
      #
      # Owner orgs use catalog-first resolution (fail-closed) because the
      # price_id is from the local Stripe account and must exist in catalog.
      #
      # Federated orgs use metadata-first resolution because cross-region
      # price IDs won't exist in the local catalog. The universal plan name
      # (e.g., 'identity_plus_v1') is stored in Stripe metadata.
      #
      def apply_plan_id
        if @planid_override
          @org.planid = @planid_override
          return
        end

        plan_id = if @owner
                    # Owner path: catalog lookup (fail-closed on miss)
                    price    = @subscription.items.data.first&.price
                    price_id = price&.id
                    return unless price_id

                    Billing::PlanValidator.resolve_plan_id(price_id)
                  else
                    # Federated path: metadata lookup (logs on miss, no raise)
                    Billing::PlanValidator.resolve_plan_id_for_federation(@subscription)
                  end

        @org.planid = plan_id if plan_id
      end

      # Cache Stripe's complimentary marker locally (Stripe → org, never reverse)
      #
      # Reads metadata['complimentary'] from the Stripe subscription and
      # stores it on the org for fast local queries. This is the only
      # codepath that should write org.complimentary.
      def apply_complimentary_marker
        meta               = @subscription.metadata
        @org.complimentary = if meta && meta[Billing::Metadata::FIELD_COMPLIMENTARY].to_s == 'true'
                               'true'
                             end
      end

      # Fields only set on owner orgs (not federated)
      def apply_owner_fields
        @org.stripe_subscription_id = @subscription.id
        @org.stripe_customer_id     = @subscription.customer
      end
    end
  end
end
