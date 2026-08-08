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

export function isFreePlan(planId: string | undefined | null): boolean {
  if (!planId) return true;
  return planId === 'free' || planId.startsWith('free_');
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
      tier: 'single_account', // Same tier as identity_plus_v1 (backend: single_account)
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

/**
 * Format an amount in cents as a localized currency string.
 *
 * Pure helper: no app imports, safe to call from anywhere. For display in
 * components, prefer the locale-aware wrapper in `@/utils/format/currency`
 * which resolves the active i18n locale automatically.
 *
 * Defensive by design (#4048):
 * - Falsy currency (null/undefined/'') coerces to 'USD' instead of throwing.
 * - Locale codes are normalized from underscore form (de_AT) to BCP-47 (de-AT).
 * - An invalid locale falls back to the browser locale; an invalid currency
 *   code degrades to a plain "12.34 XYZ" rendering instead of crashing.
 *
 * @param amount - Amount in cents
 * @param currency - ISO 4217 currency code; falsy values coerce to 'USD'
 * @param locale - BCP-47 or underscore-form locale; omitted = browser locale
 */
export function formatCurrency(
  amount: number,
  currency?: string | null,
  locale?: string
): string {
  const currencyCode = (currency || 'USD').toUpperCase();
  const normalizedLocale = locale ? locale.replace(/_/g, '-') : undefined;

  const localeCandidates: (string | undefined)[] = normalizedLocale
    ? [normalizedLocale, undefined]
    : [undefined];

  for (const candidate of localeCandidates) {
    try {
      return new Intl.NumberFormat(candidate, {
        style: 'currency',
        currency: currencyCode,
      }).format(amount / 100); // Amount is in cents
    } catch (error) {
      if (!(error instanceof RangeError)) throw error;
      // RangeError: invalid locale (retry without) or invalid currency (fall
      // through to plain rendering below).
    }
  }

  return `${(amount / 100).toFixed(2)} ${currencyCode}`;
}
