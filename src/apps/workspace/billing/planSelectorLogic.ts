// src/apps/workspace/billing/planSelectorLogic.ts

//
// Pure decision logic for PlanSelector.vue.
//
// Extracted so the component and its unit tests share ONE implementation.
// Previously the specs re-implemented these predicates inline, which let the
// test copy drift from production (e.g. the pre-#3824 tier-based isPlanCurrent
// lingering in tests after the component moved to strict id match).
//

import type { Plan as BillingPlan } from '@/services/billing.service';

/**
 * STRICT id match: the "Current" badge belongs to the plan whose id equals the
 * org's planid. No tier comparison — tier is drift-prone metadata (#3824).
 */
export function isPlanCurrent(
  plan: BillingPlan,
  orgPlanId: string | null | undefined
): boolean {
  return plan.id === orgPlanId;
}

/**
 * Two currencies conflict only when both are present and differ. A missing
 * currency (new subscriber, or a plan without one) never conflicts.
 */
function currenciesConflict(
  a: string | null | undefined,
  b: string | null | undefined
): boolean {
  return !!a && !!b && a !== b;
}

/**
 * True when the plan's currency differs from the current subscription's
 * currency. New subscribers (no current currency) never mismatch.
 */
export function isPlanCurrencyMismatch(
  currentCurrency: string | null | undefined,
  plan: BillingPlan
): boolean {
  return currenciesConflict(currentCurrency, plan.currency);
}

/**
 * True when completing a pending currency migration would create a checkout
 * that conflicts with the still-active subscription's currency. Shared by
 * handleCompletePendingMigration's guard.
 */
export function isCurrencyMigrationBlocked(
  currentCurrency: string | null | undefined,
  targetCurrency: string | null | undefined
): boolean {
  return currenciesConflict(currentCurrency, targetCurrency);
}

export interface PlanButtonState {
  orgPlanId: string | null | undefined;
  currentCurrency: string | null | undefined;
  isCreatingCheckout: boolean;
  isReactivating: boolean;
  isCancelScheduled: boolean;
  hasActiveSubscription: boolean;
}

/**
 * Whether a plan card's action button is disabled. Mirrors the production
 * cascade exactly: the current plan is actionable only while a cancellation is
 * scheduled (to reactivate); free is actionable only for active subscribers
 * (to downgrade); currency mismatches are never actionable.
 */
export function isPlanButtonDisabled(
  plan: BillingPlan,
  state: PlanButtonState
): boolean {
  return (
    (isPlanCurrent(plan, state.orgPlanId) && !state.isCancelScheduled) ||
    state.isCreatingCheckout ||
    state.isReactivating ||
    (plan.tier === 'free' && !state.hasActiveSubscription) ||
    isPlanCurrencyMismatch(state.currentCurrency, plan)
  );
}
