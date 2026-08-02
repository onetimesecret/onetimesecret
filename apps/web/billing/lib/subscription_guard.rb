# apps/web/billing/lib/subscription_guard.rb
#
# frozen_string_literal: true

require 'stripe'

module Billing
  # Duplicate-subscription guard predicate (issue #2605).
  #
  # Issue #2605 replaced the deterministic daily idempotency key on
  # checkout-session creation with a random UUID (correct: sessions are
  # pre-payment and expire on their own). That daily key was, however, the only
  # accidental same-day guard preventing an org from completing two checkouts.
  # Without a real guard, a second completed checkout produces a SECOND live
  # Stripe subscription and the webhook silently overwrites
  # org.stripe_subscription_id — a double charge plus an orphaned, still-live
  # subscription.
  #
  # The predicate lives here rather than in Billing::Controllers::Base because
  # it must apply to EVERY checkout-creation path, including the ones with no
  # request: Billing::Operations::CreateCheckoutLink (colonel endpoint + CLI).
  # Callers:
  #   - BillingController#create_checkout_session -> 409 JSON error
  #   - Plans#checkout_redirect                   -> redirect to plan-change UI
  #   - Operations::CreateCheckoutLink            -> :failed result
  # The blocking decision lives here; each caller chooses how to respond.
  module SubscriptionGuard
    extend self

    # Returns true when +org+ owns a genuinely active subscription that is NOT
    # winding down — the case in which a NEW checkout session must be blocked.
    #
    # Returns false (checkout allowed) when:
    #   - the org has no genuinely active subscription (new subscriber,
    #     canceled, past_due), including federated orgs that don't own a Stripe
    #     subscription (no stripe_subscription_id);
    #   - a graceful currency migration is pending — the old subscription was
    #     set to cancel_at_period_end and its intent stored, and the new
    #     checkout completes the migration in the target currency;
    #   - the owned subscription is already scheduled to cancel
    #     (cancel_at_period_end) — resubscribe-after-cancel.
    #
    # @param org [Onetime::Organization] Organization initiating checkout
    # @param logger [#warn, nil] optional logger for the Stripe-failure path
    # @return [Boolean] true when a new checkout must be blocked
    def blocking_active_subscription?(org, logger: nil)
      return false unless org.active_subscription?
      return false if org.stripe_subscription_id.to_s.empty?
      return false if org.pending_currency_migration?

      !subscription_scheduled_to_cancel?(org, logger: logger)
    end

    # Whether the org's current Stripe subscription is scheduled to cancel at
    # period end (or is already canceled).
    #
    # Requires a Stripe API call. On a missing key or any Stripe error, returns
    # false (treat as NOT winding down) so the duplicate-subscription guard
    # fails safe toward BLOCKING a possible duplicate charge; the caller can
    # retry once the transient condition clears.
    #
    # @param org [Onetime::Organization] Organization with a stripe_subscription_id
    # @param logger [#warn, nil]
    # @return [Boolean]
    def subscription_scheduled_to_cancel?(org, logger: nil)
      return false if Stripe.api_key.to_s.strip.empty?

      subscription = Stripe::Subscription.retrieve(org.stripe_subscription_id)
      subscription.cancel_at_period_end == true ||
        subscription.status.to_s == 'canceled'
    rescue Stripe::StripeError => ex
      logger&.warn(
        'Could not verify subscription cancellation state for duplicate-subscription guard',
        {
          extid: org.extid,
          stripe_subscription_id: org.stripe_subscription_id,
          error: ex.message,
        },
      )
      false
    end
  end
end
