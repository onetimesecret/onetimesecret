// src/schemas/shapes/account/billing.ts

/**
 * Billing shapes with runtime transforms
 *
 * These schemas transform API wire format (Unix timestamps) into
 * runtime types (Date objects). Contract definitions are in contracts/billing.ts.
 *
 * Helper functions (getPlanLabel, formatCurrency, etc.) remain in
 * @/types/billing to avoid circular dependencies.
 */

import {
  invoiceContractSchema,
  subscriptionContractSchema,
} from '@/schemas/contracts/billing';

// Re-export all contracts for backwards compatibility
export * from '@/schemas/contracts/billing';

/**
 * Subscription schema
 *
 * Transforms subscription contract timestamps to Date objects.
 */
export const subscriptionSchema = subscriptionContractSchema.transform((data) => ({
  ...data,
  current_period_start: new Date(data.current_period_start * 1000),
  current_period_end: new Date(data.current_period_end * 1000),
  created_at: new Date(data.created_at * 1000),
  updated_at: new Date(data.updated_at * 1000),
}));

export type Subscription = ReturnType<typeof subscriptionSchema.parse>;

/**
 * Invoice schema
 *
 * Transforms invoice contract timestamps to Date objects.
 */
export const invoiceSchema = invoiceContractSchema.transform((data) => ({
  ...data,
  invoice_date: new Date(data.invoice_date * 1000),
  due_date: new Date(data.due_date * 1000),
  paid_date: data.paid_date ? new Date(data.paid_date * 1000) : undefined,
}));

export type Invoice = ReturnType<typeof invoiceSchema.parse>;
