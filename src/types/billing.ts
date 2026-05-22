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
 * Canonical plan ID to human-readable display name mapping.
 *
 * Plan IDs are the canonical identifiers (e.g., `identity_plus_v1`).
 * Billing tiers (`free`, `single_account`, `single_team`, `multi_team`)
 * are descriptive metadata, not used for selection.
 */
const PLAN_LABELS: Record<string, string> = {
  // Canonical plan IDs
  free_v1: 'Free',
  identity_plus_v1: 'Identity Plus',
  team_plus_v1: 'Team Plus',
  legacy_plan_v1: 'Legacy Plan',
  // Legacy/grandfathered identifiers
  identity: 'Identity Plus (Early Supporter)',
  free: 'Free', // null-planid fallback in admin views
};

/**
 * Resolve a canonical plan ID to a human-readable display name.
 *
 * @param planType - A canonical plan ID (e.g., `identity_plus_v1`)
 * @returns The display name, or the plan ID unchanged if not mapped
 */
export function getPlanLabel(planType: PlanType | string): string {
  return PLAN_LABELS[planType] ?? planType;
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
