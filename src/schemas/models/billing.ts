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
export const invoiceStatusSchema = z.enum([
  'draft', 'open', 'paid', 'uncollectible', 'void',
  // Legacy/mapped statuses used in UI
  'pending', 'failed',
]);

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

/**
 * Currency migration schemas
 *
 * Used when a customer tries to subscribe to a plan in a different currency
 * than their existing Stripe subscription.
 */

/** Warnings about potential issues during currency migration */
export const currencyMigrationWarningsSchema = z.object({
  has_credit_balance: z.boolean(),
  credit_balance_amount: z.number(),
  has_pending_invoice_items: z.boolean(),
  has_incompatible_coupons: z.boolean(),
});

export type CurrencyMigrationWarnings = z.infer<typeof currencyMigrationWarningsSchema>;

/** 409 currency conflict error response from checkout endpoint */
export const currencyConflictErrorSchema = z.object({
  error: z.literal(true),
  code: z.literal('currency_conflict'),
  message: z.string().optional(),
  details: z.object({
    existing_currency: z.string(),
    requested_currency: z.string(),
    current_plan: z.object({
      name: z.string(),
      price_formatted: z.string(),
      current_period_end: z.number(),
    }).nullable(),
    requested_plan: z.object({
      name: z.string(),
      price_formatted: z.string(),
      price_id: z.string(),
    }).nullable(),
    warnings: currencyMigrationWarningsSchema,
  }),
});

export type CurrencyConflictError = z.infer<typeof currencyConflictErrorSchema>;

/** Migration mode */
export const migrationModeSchema = z.enum(['graceful', 'immediate']);

export type MigrationMode = z.infer<typeof migrationModeSchema>;

/** Request body for POST /api/org/:extid/migrate-currency */
export const migrateCurrencyRequestSchema = z.object({
  mode: migrationModeSchema,
  new_price_id: z.string(),
});

export type MigrateCurrencyRequest = z.infer<typeof migrateCurrencyRequestSchema>;

/** Graceful migration response */
export const gracefulMigrationResponseSchema = z.object({
  success: z.literal(true),
  migration: z.object({
    mode: z.literal('graceful'),
    cancel_at: z.number(),
  }),
});

/** Immediate migration response */
export const immediateMigrationResponseSchema = z.object({
  success: z.literal(true),
  migration: z.object({
    mode: z.literal('immediate'),
    checkout_url: z.string(),
    refund_amount: z.number(),
    refund_formatted: z.string(),
  }),
});

/** Union response for migrate-currency endpoint. Discriminate on migration.mode at runtime. */
export const migrateCurrencyResponseSchema = z.union([
  gracefulMigrationResponseSchema,
  immediateMigrationResponseSchema,
]);

export type GracefulMigrationResponse = z.infer<typeof gracefulMigrationResponseSchema>;
export type ImmediateMigrationResponse = z.infer<typeof immediateMigrationResponseSchema>;
export type MigrateCurrencyResponse = z.infer<typeof migrateCurrencyResponseSchema>;

/** Pending migration state on subscription status */
export const pendingMigrationSchema = z.object({
  target_price_id: z.string(),
  target_plan_name: z.string(),
  target_currency: z.string(),
  target_plan_id: z.string(),
  effective_after: z.number(),
});

export type PendingMigration = z.infer<typeof pendingMigrationSchema>;
