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
    #   # Owner path (full update with Stripe IDs)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: true)
    #
    #   # Federated path (status + plan only, no Stripe IDs)
    #   ApplySubscriptionToOrg.call(org, subscription, owner: false)
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
      # @return [Boolean] Result of org.save
      def self.call(org, subscription, owner: true, planid_override: nil)
        new(org, subscription, owner: owner, planid_override: planid_override).call
      end

      def initialize(org, subscription, owner: true, planid_override: nil)
        @org              = org
        @subscription     = subscription
        @owner            = owner
        @planid_override  = planid_override
      end

      def call
        apply_status_fields
        apply_plan_id
        apply_complimentary_marker
        apply_owner_fields if @owner

        @org.save
      end

      private

      # Fields common to both owner and federated orgs
      def apply_status_fields
        @org.subscription_status = @subscription.status

        period_end = @subscription.items.data.first&.current_period_end
        @org.subscription_period_end = period_end.to_s if period_end
      end

      # Resolve plan from catalog (fail-closed), or use explicit override
      def apply_plan_id
        if @planid_override
          @org.planid = @planid_override
          return
        end

        price    = @subscription.items.data.first&.price
        price_id = price&.id
        return unless price_id

        plan_id     = Billing::PlanValidator.resolve_plan_id(price_id)
        @org.planid = plan_id if plan_id
      end

      # Sync complimentary marker from subscription metadata
      def apply_complimentary_marker
        meta = @subscription.metadata
        if meta && meta[Billing::Metadata::FIELD_COMPLIMENTARY].to_s == 'true'
          @org.complimentary = 'true'
        else
          @org.complimentary = nil
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
