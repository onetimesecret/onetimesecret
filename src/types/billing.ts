// src/types/billing.ts

/**
 * Billing and subscription type definitions
 *
 * Types are derived from Zod schemas in @/schemas/models/billing.
 * This file re-exports them and provides helper functions for display.
 */

// Re-export all schemas and types from canonical location
export {
  // Schemas
  billingIntervalSchema,
  invoiceSchema,
  invoiceStatusSchema,
  paymentMethodCardSchema,
  paymentMethodSchema,
  planSchema,
  planTypeSchema,
  subscriptionSchema,
  subscriptionStatusSchema,
  // Types (derived from schemas via z.infer<>)
  type BillingInterval,
  type Invoice,
  type InvoiceStatus,
  type PaymentMethod,
  type PaymentMethodCard,
  type Plan,
  type PlanType,
  type Subscription,
  type SubscriptionStatus,
} from '@/schemas/models/billing';

/**
 * Display helpers
 */
import type { InvoiceStatus, PlanType, SubscriptionStatus } from '@/schemas/models/billing';

export function getPlanLabel(planType: PlanType | string): string {
  const labels: Record<string, string> = {
    free: 'Free',
    single_team: 'Single Team',
    multi_team: 'Multi Team',
    identity_plus: 'Identity Plus',
    team_plus: 'Team Plus',
  };

  // Direct match
  if (labels[planType]) {
    return labels[planType];
  }

  // Fallback: convert snake_case to Title Case
  return planType.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
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
