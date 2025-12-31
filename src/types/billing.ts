// src/types/billing.ts

/**
 * Billing and subscription type definitions
 * Used across billing components, stores, and views
 */

import { z } from 'zod';

/**
 * Subscription plan types
 */
export type PlanType = 'free' | 'single_team' | 'multi_team';

/**
 * Subscription status
 */
export type SubscriptionStatus = 'active' | 'inactive' | 'past_due' | 'canceled';

/**
 * Invoice status
 */
export type InvoiceStatus = 'paid' | 'pending' | 'failed';

/**
 * Billing interval
 */
export type BillingInterval = 'month' | 'year';

/**
 * Subscription interface
 */
export interface Subscription {
  id: string;
  org_id: string;
  plan_type: PlanType;
  status: SubscriptionStatus;
  teams_limit: number;
  teams_used: number;
  members_per_team_limit: number;
  billing_interval: BillingInterval;
  current_period_start: Date;
  current_period_end: Date;
  cancel_at_period_end: boolean;
  created_at: Date;
  updated_at: Date;
}

/**
 * Plan definition
 */
export interface Plan {
  id: string;
  type: PlanType;
  name: string;
  description: string;
  price_monthly: number;
  price_yearly: number;
  teams_limit: number;
  members_per_team_limit: number;
  features: string[];
}

/**
 * Invoice interface
 */
export interface Invoice {
  id: string;
  org_id: string;
  amount: number;
  currency: string;
  status: InvoiceStatus;
  invoice_date: Date;
  due_date: Date;
  paid_date?: Date;
  invoice_url?: string;
  download_url?: string;
}

/**
 * Payment method interface
 */
export interface PaymentMethod {
  id: string;
  type: 'card';
  card?: {
    brand: string;
    last4: string;
    exp_month: number;
    exp_year: number;
  };
  is_default: boolean;
}

/**
 * Zod schemas for validation
 */

export const subscriptionSchema = z.object({
  id: z.string(),
  org_id: z.string(),
  plan_type: z.enum(['free', 'single_team', 'multi_team']),
  status: z.enum(['active', 'inactive', 'past_due', 'canceled']),
  teams_limit: z.number(),
  teams_used: z.number(),
  members_per_team_limit: z.number(),
  billing_interval: z.enum(['month', 'year']),
  current_period_start: z.number().transform(val => new Date(val * 1000)),
  current_period_end: z.number().transform(val => new Date(val * 1000)),
  cancel_at_period_end: z.boolean(),
  created_at: z.number().transform(val => new Date(val * 1000)),
  updated_at: z.number().transform(val => new Date(val * 1000)),
});

export const planSchema = z.object({
  id: z.string(),
  type: z.enum(['free', 'single_team', 'multi_team']),
  name: z.string(),
  description: z.string(),
  price_monthly: z.number(),
  price_yearly: z.number(),
  teams_limit: z.number(),
  members_per_team_limit: z.number(),
  features: z.array(z.string()),
});

export const invoiceSchema = z.object({
  id: z.string(),
  org_id: z.string(),
  amount: z.number(),
  currency: z.string(),
  status: z.enum(['paid', 'pending', 'failed']),
  invoice_date: z.number().transform(val => new Date(val * 1000)),
  due_date: z.number().transform(val => new Date(val * 1000)),
  paid_date: z.number().transform(val => new Date(val * 1000)).optional(),
  invoice_url: z.string().url().optional(),
  download_url: z.string().url().optional(),
});

export const paymentMethodSchema = z.object({
  id: z.string(),
  type: z.literal('card'),
  card: z.object({
    brand: z.string(),
    last4: z.string(),
    exp_month: z.number(),
    exp_year: z.number(),
  }).optional(),
  is_default: z.boolean(),
});

/**
 * Display helpers
 */

export function getPlanLabel(planType: PlanType): string {
  const labels: Record<PlanType, string> = {
    free: 'Free',
    single_team: 'Single Team',
    multi_team: 'Multi Team',
  };
  return labels[planType];
}

/**
 * Parse a plan ID to a human-readable display name
 *
 * Handles plan IDs like:
 * - identity_plus_v1_monthly -> Identity Plus
 * - team_plus_v1_yearly -> Team Plus
 * - single_team_v1_monthly -> Single Team
 * - free_v1 -> Free
 *
 * @param planId - The plan ID from the backend (e.g., 'identity_plus_v1_monthly')
 * @returns A human-readable display name
 */
export function getPlanDisplayName(planId: string): string {
  if (!planId) return 'Free';

  // Known plan name mappings (plan ID patterns -> display name)
  const planPatterns: [RegExp, string][] = [
    [/^free/i, 'Free'],
    [/identity_plus/i, 'Identity Plus'],
    [/team_plus|multi_team/i, 'Team Plus'],
    [/single_team/i, 'Single Team'],
    [/identity(?!_plus)/i, 'Identity'],
  ];

  for (const [pattern, displayName] of planPatterns) {
    if (pattern.test(planId)) {
      return displayName;
    }
  }

  // Fallback: Convert snake_case to Title Case (removing version/interval suffixes)
  // e.g., 'some_plan_v1_monthly' -> 'Some Plan'
  const baseName = planId
    .replace(/_v\d+.*$/, '') // Remove version and interval suffix
    .replace(/_/g, ' ') // Convert underscores to spaces
    .replace(/\b\w/g, (c) => c.toUpperCase()); // Title case

  return baseName || planId;
}

export function getSubscriptionStatusLabel(status: SubscriptionStatus): string {
  const labels: Record<SubscriptionStatus, string> = {
    active: 'Active',
    inactive: 'Inactive',
    past_due: 'Past Due',
    canceled: 'Canceled',
  };
  return labels[status];
}

export function getInvoiceStatusLabel(status: InvoiceStatus): string {
  const labels: Record<InvoiceStatus, string> = {
    paid: 'Paid',
    pending: 'Pending',
    failed: 'Failed',
  };
  return labels[status];
}

export function formatCurrency(amount: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat('en-US', {
    style: 'currency',
    currency,
  }).format(amount / 100); // Assuming amount is in cents
}
