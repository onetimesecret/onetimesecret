import type Stripe from 'stripe';

export function getStripeCustomer(): Stripe.Customer {
  return window.stripe_customer as Stripe.Customer;
}

export function getStripeSubscriptions(): Stripe.Subscription[] {
  return window.stripe_subscriptions as Stripe.Subscription[];
}
