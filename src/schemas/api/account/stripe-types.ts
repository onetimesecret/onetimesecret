/**
 * Minimal Stripe Type Definitions for OpenAPI Documentation
 *
 * These schemas represent the minimal subset of Stripe objects we expose
 * in our API responses. They're designed for OpenAPI documentation, not
 * runtime validation of actual Stripe responses.
 *
 * See full Stripe API docs:
 * - Customer: https://stripe.com/docs/api/customers/object
 * - Subscription: https://stripe.com/docs/api/subscriptions/object
 */

import { z } from '@/schemas/openapi-setup';

/**
 * Minimal Stripe Customer schema for API documentation
 * Only includes fields we commonly expose or use
 */
export const stripeCustomerSchema = z.object({
  id: z.string().describe('Unique Stripe customer ID'),
  email: z.string().email().nullable().describe('Customer email address'),
  name: z.string().nullable().describe('Customer name'),
  created: z.number().describe('Timestamp of customer creation'),
  currency: z.string().nullable().describe('Customer currency preference'),
  balance: z.number().nullable().describe('Customer account balance'),
  metadata: z.record(z.string(), z.string()).describe('Custom metadata key-value pairs')
}).openapi('StripeCustomer');

/**
 * Minimal Stripe Subscription schema for API documentation
 * Only includes fields we commonly expose or use
 */
export const stripeSubscriptionSchema = z.object({
  id: z.string().describe('Unique Stripe subscription ID'),
  customer: z.string().describe('ID of the customer who owns this subscription'),
  status: z.enum([
    'incomplete',
    'incomplete_expired',
    'trialing',
    'active',
    'past_due',
    'canceled',
    'unpaid',
    'paused'
  ]).describe('Subscription status'),
  created: z.number().describe('Timestamp of subscription creation'),
  current_period_start: z.number().describe('Start of the current billing period'),
  current_period_end: z.number().describe('End of the current billing period'),
  cancel_at_period_end: z.boolean().describe('Whether subscription cancels at period end'),
  canceled_at: z.number().nullable().describe('Timestamp when subscription was canceled'),
  items: z.object({
    data: z.array(z.object({
      id: z.string(),
      price: z.object({
        id: z.string(),
        currency: z.string(),
        unit_amount: z.number().nullable(),
        recurring: z.object({
          interval: z.enum(['day', 'week', 'month', 'year']),
          interval_count: z.number()
        }).nullable()
      })
    }))
  }).describe('Subscription line items'),
  metadata: z.record(z.string(), z.string()).describe('Custom metadata key-value pairs')
}).openapi('StripeSubscription');

/**
 * Export types for TypeScript
 * Using TypeScript's built-in inference instead of z.infer to avoid namespace issues
 */
export type StripeCustomer = typeof stripeCustomerSchema._output;
export type StripeSubscription = typeof stripeSubscriptionSchema._output;
