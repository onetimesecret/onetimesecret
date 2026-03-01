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
import type { InvoiceStatus, PlanType, SubscriptionStatus } from '@/schemas/models/billing';
import type { ComposerTranslation } from 'vue-i18n';

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
  return planType.replace(/_/g, ' ').replace(/\b\w/g, (c: string) => c.toUpperCase());
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

  // Check for legacy plans first (centralized logic)
  const legacyInfo = getLegacyPlanInfo(planId);
  if (legacyInfo) {
    return legacyInfo.displayName;
  }

  // Known plan name mappings (plan ID patterns -> display name)
  // Order matters: more specific patterns must come before general ones
  const planPatterns: [RegExp, string][] = [
    [/^free/i, 'Free'],
    [/identity_plus/i, 'Identity Plus'],
    [/team_plus|multi_team/i, 'Team Plus'],
    [/single_team/i, 'Single Team'],
    [/identity(?!_plus)/i, 'Identity'], // Other identity-prefixed plans
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
