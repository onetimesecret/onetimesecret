// src/schemas/models/billing.ts

/**
 * Billing Zod schemas and derived types
 *
 * Schemas are the source of truth for billing data structures.
 * Types are inferred from schemas using z.infer<>.
 *
 * Helper functions (getPlanLabel, formatCurrency, etc.) remain in
 * @/types/billing to avoid circular dependencies.
 */

import { z } from 'zod';

/**
 * Plan type schema
 */
export const planTypeSchema = z.enum(['free', 'single_team', 'multi_team']);

export type PlanType = z.infer<typeof planTypeSchema>;

/**
 * Subscription status schema
 */
export const subscriptionStatusSchema = z.enum([
  'active',
  'inactive',
  'past_due',
  'canceled',
]);

export type SubscriptionStatus = z.infer<typeof subscriptionStatusSchema>;

/**
 * Invoice status schema
 */
export const invoiceStatusSchema = z.enum(['paid', 'pending', 'failed']);

export type InvoiceStatus = z.infer<typeof invoiceStatusSchema>;

/**
 * Billing interval schema
 */
export const billingIntervalSchema = z.enum(['month', 'year']);

export type BillingInterval = z.infer<typeof billingIntervalSchema>;

/**
 * Subscription schema
 *
 * Validates subscription data from API responses.
 * Timestamps are Unix epoch seconds, transformed to Date objects.
 */
export const subscriptionSchema = z.object({
  id: z.string(),
  org_id: z.string(),
  plan_type: planTypeSchema,
  status: subscriptionStatusSchema,
  teams_limit: z.number(),
  teams_used: z.number(),
  members_per_team_limit: z.number(),
  billing_interval: billingIntervalSchema,
  current_period_start: z.number().transform((val) => new Date(val * 1000)),
  current_period_end: z.number().transform((val) => new Date(val * 1000)),
  cancel_at_period_end: z.boolean(),
  created_at: z.number().transform((val) => new Date(val * 1000)),
  updated_at: z.number().transform((val) => new Date(val * 1000)),
});

export type Subscription = z.infer<typeof subscriptionSchema>;

/**
 * Plan schema
 *
 * Validates plan definition data.
 */
export const planSchema = z.object({
  id: z.string(),
  type: planTypeSchema,
  name: z.string(),
  description: z.string(),
  price_monthly: z.number(),
  price_yearly: z.number(),
  teams_limit: z.number(),
  members_per_team_limit: z.number(),
  features: z.array(z.string()),
});

export type Plan = z.infer<typeof planSchema>;

/**
 * Invoice schema
 *
 * Validates invoice data from API responses.
 * Timestamps are Unix epoch seconds, transformed to Date objects.
 */
export const invoiceSchema = z.object({
  id: z.string(),
  org_id: z.string(),
  amount: z.number(),
  currency: z.string(),
  status: invoiceStatusSchema,
  invoice_date: z.number().transform((val) => new Date(val * 1000)),
  due_date: z.number().transform((val) => new Date(val * 1000)),
  paid_date: z
    .number()
    .transform((val) => new Date(val * 1000))
    .optional(),
  invoice_url: z.url().optional(),
  download_url: z.url().optional(),
});

export type Invoice = z.infer<typeof invoiceSchema>;

/**
 * Payment method card schema
 */
export const paymentMethodCardSchema = z.object({
  brand: z.string(),
  last4: z.string(),
  exp_month: z.number(),
  exp_year: z.number(),
});

export type PaymentMethodCard = z.infer<typeof paymentMethodCardSchema>;

/**
 * Payment method schema
 *
 * Validates payment method data from API responses.
 */
export const paymentMethodSchema = z.object({
  id: z.string(),
  type: z.literal('card'),
  card: paymentMethodCardSchema.optional(),
  is_default: z.boolean(),
});

export type PaymentMethod = z.infer<typeof paymentMethodSchema>;
