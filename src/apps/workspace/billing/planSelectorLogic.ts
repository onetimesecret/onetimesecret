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
export function isPlanCurrent(plan: BillingPlan, orgPlanId: string | null | undefined): boolean {
  return plan.id === orgPlanId;
}

/**
 * Two currencies conflict only when both are present and differ. A missing
 * currency (new subscriber, or a plan without one) never conflicts.
 */
function currenciesConflict(a: string | null | undefined, b: string | null | undefined): boolean {
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
export function isPlanButtonDisabled(plan: BillingPlan, state: PlanButtonState): boolean {
  return (
    (isPlanCurrent(plan, state.orgPlanId) && !state.isCancelScheduled) ||
    state.isCreatingCheckout ||
    state.isReactivating ||
    (plan.tier === 'free' && !state.hasActiveSubscription) ||
    isPlanCurrencyMismatch(state.currentCurrency, plan)
  );
}

/**
 * Canonical tier ordering for upgrade/downgrade direction (#3824).
 * free < single_account < single_team < multi_team.
 * Single source of truth — the component and its specs both consume this rather
 * than re-declaring the order (drift is exactly the #3824 failure mode).
 */
export const TIER_ORDER = ['free', 'single_account', 'single_team', 'multi_team'] as const;

/**
 * Rank of a tier in TIER_ORDER. Falsy (unresolved/legacy) and unknown tiers
 * both yield -1, which callers treat as "no direction".
 */
export function tierRank(tier: string | null | undefined): number {
  return tier ? TIER_ORDER.indexOf(tier as (typeof TIER_ORDER)[number]) : -1;
}

/**
 * Whether moving from currentTier to targetPlan's tier is an upgrade. An
 * unresolved current or target tier (rank -1) yields no direction, matching the
 * component's "currentPlan null => no upgrade/downgrade" behavior.
 */
export function canUpgrade(
  currentTier: string | null | undefined,
  targetPlan: BillingPlan
): boolean {
  const current = tierRank(currentTier);
  const target = tierRank(targetPlan.tier);
  if (current === -1 || target === -1) return false;
  return target > current;
}

/**
 * Whether moving from currentTier to targetPlan's tier is a downgrade.
 * Same unresolved-tier handling as canUpgrade.
 */
export function canDowngrade(
  currentTier: string | null | undefined,
  targetPlan: BillingPlan
): boolean {
  const current = tierRank(currentTier);
  const target = tierRank(targetPlan.tier);
  if (current === -1 || target === -1) return false;
  return target < current;
}

/**
 * Whether a plan shows the "Most Popular" badge. is_popular (API-provided) is
 * the sole authority — no tier-based fallback, so the badge is never defaulted
 * onto a card (#3824).
 */
export function isPlanRecommended(plan: BillingPlan): boolean {
  return plan.is_popular ?? false;
}

/**
 * The action handlePlanSelect resolves to before running side effects. Pure
 * classification so the component and its spec share one control-flow contract:
 *   - 'noop'                   no org, current-plan (not cancel-scheduled), or
 *                             free-tier without an active subscription
 *   - 'reactivate'             current plan while a cancellation is scheduled
 *   - 'open-cancel-modal'      free tier with an active subscription
 *   - 'currency-blocked'       target currency conflicts with the subscription
 *   - 'open-plan-change-modal' existing subscriber switching paid plans
 *   - 'checkout'               new subscriber starting a Stripe Checkout
 */
export type PlanSelectAction =
  | 'reactivate'
  | 'open-cancel-modal'
  | 'currency-blocked'
  | 'open-plan-change-modal'
  | 'checkout'
  | 'noop';

export interface PlanSelectContext {
  orgExtid: string | null | undefined;
  orgPlanId: string | null | undefined;
  currentCurrency: string | null | undefined;
  isCancelScheduled: boolean;
  hasActiveSubscription: boolean;
}

/**
 * Classify what a plan-card click should do, matching handlePlanSelect's
 * early-return cascade exactly. The component switches on the returned action to
 * run the impure work (modals, checkout redirect, error strings); the spec
 * asserts the action, so the ordering can't drift out from under the tests.
 */
export function resolvePlanSelectAction(
  plan: BillingPlan,
  ctx: PlanSelectContext
): PlanSelectAction {
  if (!ctx.orgExtid) return 'noop';

  if (isPlanCurrent(plan, ctx.orgPlanId)) {
    return ctx.isCancelScheduled ? 'reactivate' : 'noop';
  }

  if (plan.tier === 'free') {
    return ctx.hasActiveSubscription ? 'open-cancel-modal' : 'noop';
  }

  if (isPlanCurrencyMismatch(ctx.currentCurrency, plan)) return 'currency-blocked';

  if (ctx.hasActiveSubscription) return 'open-plan-change-modal';

  return 'checkout';
}

/**
 * The action handleCompletePendingMigration resolves to before side effects:
 *   - 'noop'             no org or no pending migration
 *   - 'currency-blocked' the still-active subscription's currency conflicts
 *                        with the migration target (checkout would fail)
 *   - 'checkout'         safe to create the migration checkout session
 */
export type CompletePendingMigrationAction = 'noop' | 'currency-blocked' | 'checkout';

export interface CompletePendingMigrationContext {
  orgExtid: string | null | undefined;
  currentCurrency: string | null | undefined;
}

/**
 * Classify the "Complete Migration" click, matching
 * handleCompletePendingMigration's guard order. Reuses isCurrencyMigrationBlocked
 * for the currency decision so production and spec share one implementation.
 */
export function resolveCompletePendingMigrationAction(
  pendingMigration: { target_currency?: string | null } | null | undefined,
  ctx: CompletePendingMigrationContext
): CompletePendingMigrationAction {
  if (!ctx.orgExtid || !pendingMigration) return 'noop';
  if (isCurrencyMigrationBlocked(ctx.currentCurrency, pendingMigration.target_currency)) {
    return 'currency-blocked';
  }
  return 'checkout';
}

export interface CancelLinkState {
  hasActiveSubscription: boolean;
  isLegacyCustomer: boolean;
  currentTier: string | null | undefined;
  isCancelScheduled: boolean;
}

/**
 * Whether the "Cancel Subscription" link is shown. Mirrors the template guard
 * exactly: an active subscriber OR a grandfathered legacy customer, on a paid
 * tier, whose cancellation is not already scheduled. Free tier never shows it,
 * and a customer already scheduled to cancel sees the reactivate banner instead.
 */
export function shouldShowCancelLink(state: CancelLinkState): boolean {
  return (
    (state.hasActiveSubscription || state.isLegacyCustomer) &&
    state.currentTier !== 'free' &&
    !state.isCancelScheduled
  );
}
