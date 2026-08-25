# apps/web/billing/operations/webhook_handlers/subscription_created.rb
#
# frozen_string_literal: true

require_relative 'subscription_handler'
require_relative 'subscription_federation'

module Billing
  module Operations
    module WebhookHandlers
      # Handles customer.subscription.created events.
      #
      # This handler exists for ONE reason: cross-region federation. Before it,
      # federation ran on updated/deleted/paused/resumed only, so a purchase in
      # region B by someone who already had an organization in region A never
      # propagated. That org stayed on the free tier until some later event on
      # the same subscription happened to fire — the first renewal, a plan
      # change, a pause. In practice: until the customer complained.
      #
      # Two-path matching (see {SubscriptionFederation}):
      # - Path 1 (Owner): Organization with matching stripe_customer_id
      # - Path 2 (Federated): Organizations with matching email_hash and no
      #   stripe_customer_id — the orgs this handler exists to upgrade
      # - No match: subscription state is stored as a
      #   PendingFederatedSubscription, claimed when an account appears here
      #
      # ## Why the owner path only observes
      #
      # In the region where the purchase happened, `checkout.session.completed`
      # is authoritative: it resolves the target org from subscription metadata,
      # creates or adopts a workspace, writes the Stripe IDs, and — critically —
      # detects when a completed checkout is about to REPLACE a still-active
      # subscription and logs that for reconciliation (#2605).
      #
      # Both events fire for the same purchase, and delivery order is not
      # guaranteed. If this handler wrote owner fields it would frequently win
      # the race, overwrite org.stripe_subscription_id, and make
      # CheckoutCompleted's replacement detection read the NEW id as the
      # "previous" one — silently disabling a duplicate-charge safety net. So
      # the owner path logs and defers. Nothing is lost: CheckoutCompleted
      # applies the same subscription moments later.
      #
      # ## Ordering is benign for federated orgs too
      #
      # If this event lands before `checkout.session.completed`, the buyer's own
      # org has no stripe_customer_id yet and matches the FEDERATED path, so it
      # picks up a subscription_federated_at marker. That is self-healing:
      # Organization#subscription_federated? is derived as
      # `subscription_federated_at.present? && !subscription_owner?`, so the
      # marker stops reading as federated the moment CheckoutCompleted sets
      # stripe_customer_id. Both orderings converge on the same state.
      #
      # @see https://github.com/onetimesecret/onetimesecret/issues/4230
      # @see https://github.com/onetimesecret/onetimesecret/issues/2471
      #
      class SubscriptionCreated < SubscriptionHandler
        include SubscriptionFederation

        def self.handles?(event_type)
          event_type == 'customer.subscription.created'
        end

        protected

        def process
          subscription = @data_object

          return skip_without_federation(subscription) unless federation_enabled?

          process_with_federation(subscription) do |org, is_owner|
            if is_owner
              observe_owner(org, subscription)
            else
              federate_to(org, subscription)
            end
          end
        end

        private

        # Federation off: this handler has nothing to do.
        #
        # Deliberately NOT routed through #with_organization like the other
        # subscription handlers. That helper looks orgs up by
        # stripe_subscription_id, which nothing can have stored yet for a
        # brand-new subscription, so every single purchase in a single-region
        # deployment would report a non-match seconds before
        # checkout.session.completed linked it — turning the no-match warning
        # into noise and burying the real misses it is meant to surface.
        #
        # @param subscription [Stripe::Subscription]
        # @return [Symbol] :skipped
        #
        def skip_without_federation(subscription)
          billing_logger.info 'Subscription created (federation disabled, deferring to checkout.session.completed)',
            {
              subscription_id: subscription.id,
              stripe_customer_id: subscription.customer,
              status: subscription.status,
            }

          :skipped
        end

        # Owner path: record that we saw it, write nothing. See the class-level
        # note on why CheckoutCompleted owns this write path.
        #
        # @param org [Onetime::Organization] Owning organization
        # @param subscription [Stripe::Subscription]
        # @return [void]
        #
        def observe_owner(org, subscription)
          billing_logger.info 'Subscription created (owner, deferring to checkout.session.completed)',
            {
              orgid: org.objid,
              subscription_id: subscription.id,
              status: subscription.status,
            }
        end

        # Federated path: apply the subscription's benefits to an organization
        # in this region that shares the buyer's email hash but owns no Stripe
        # customer. This is the propagation the handler was added for.
        #
        # @param org [Onetime::Organization] Federated organization
        # @param subscription [Stripe::Subscription]
        # @return [void]
        #
        def federate_to(org, subscription)
          first_time = update_federated_org(org, subscription)

          billing_logger.info 'Subscription created (federated)',
            {
              orgid: org.objid,
              subscription_id: subscription.id,
              status: subscription.status,
              planid: org.planid,
              first_federation: first_time,
            }
        end
      end
    end
  end
end
