// src/types/billing.ts

/**
 * Billing and subscription type definitions
 *
 * Types are derived from Zod schemas in @/schemas/shapes/account/billing.
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
  planTypeSchema,
  subscriptionSchema,
  subscriptionStatusSchema,
  // Types (derived from schemas via z.infer<>)
  type BillingInterval,
  type Invoice,
  type InvoiceStatus,
  type PaymentMethod,
  type PaymentMethodCard,
  type PlanType,
  type Subscription,
  type SubscriptionStatus,
} from '@/schemas/shapes/account/billing';

/**
 * Legacy plan detection
 *
 * Grandfathered plans that are no longer available for new subscriptions
 * but continue to be honored for existing customers.
 */
const LEGACY_PLAN_IDS = ['identity'] as const;

/**
 * Check if a plan ID represents a legacy/grandfathered plan
 *
 * @param planId - The plan ID to check
 * @returns true if this is a legacy plan that should be displayed specially
 */
export function isLegacyPlan(planId: string): boolean {
  if (!planId) return false;
  return LEGACY_PLAN_IDS.some((legacy) => planId === legacy);
}

/**
 * Get detailed information about a legacy plan
 *
 * @param planId - The plan ID to check
 * @returns Legacy plan info object, or null if not a legacy plan
 */
export function getLegacyPlanInfo(
  planId: string
): { isLegacy: boolean; displayName: string; tier: string } | null {
  if (planId === 'identity') {
    return {
      isLegacy: true,
      displayName: 'Identity Plus (Early Supporter)',
      tier: 'single_team', // Same tier as identity_plus for feature parity
    };
  }
  return null;
}

/**
 * Display helpers
 */
import type { InvoiceStatus, PlanType, SubscriptionStatus } from '@/schemas/shapes/account/billing';
import type { ComposerTranslation } from 'vue-i18n';

/**
 * Resolve a plan tier or canonical plan ID to a human-readable display name.
 *
 * Accepts both billing tier keys (`free`, `single_team`, `multi_team`,
 * `identity_plus`, `team_plus`) and canonical plan IDs (`free_v1`,
 * `identity_plus_v1`, `team_plus_v1`, ...), plus the legacy `identity`
 * plan. Lookup is an explicit map — no string parsing of plan identity.
 *
 * @param planType - A billing tier key or canonical plan ID
 * @returns A human-readable display name
 */
export function getPlanLabel(planType: PlanType | string): string {
  const labels: Record<string, string> = {
    // Billing tier keys
    free: 'Free',
    single_team: 'Single Team',
    multi_team: 'Multi Team',
    identity_plus: 'Identity Plus',
    team_plus: 'Team Plus',
    // Canonical plan IDs
    free_v1: 'Free',
    identity_plus_v1: 'Identity Plus',
    team_plus_v1: 'Team Plus',
    legacy_plan_v1: 'Legacy Plan',
    // Legacy/grandfathered plan
    identity: 'Identity Plus (Early Supporter)',
  };

  // Direct match
  if (labels[planType]) {
    return labels[planType];
  }

  // Fallback: convert snake_case to Title Case
  return planType.replace(/_/g, ' ').replace(/\b\w/g, (c: string) => c.toUpperCase());
}

export function getSubscriptionStatusLabel(
  status: SubscriptionStatus,
  t: ComposerTranslation,
): string {
  return t(`web.billing.subscription.${status}`);
}

export function getInvoiceStatusLabel(
  status: InvoiceStatus,
  t: ComposerTranslation,
): string {
  return t(`web.billing.invoices.${status}`);
}

export function formatCurrency(amount: number, currency: string = 'USD'): string {
  return new Intl.NumberFormat(undefined, {
    style: 'currency',
    currency,
  }).format(amount / 100); // Assuming amount is in cents
}
