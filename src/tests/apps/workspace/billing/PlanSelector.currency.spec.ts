// src/tests/apps/workspace/billing/PlanSelector.currency.spec.ts

//
// Unit tests for PlanSelector.vue currency mismatch logic
//
// Tests cover:
// - isPlanCurrencyMismatch detection
// - handlePlanSelect early return on mismatch
// - handleCompletePendingMigration currency guard
// - Plan card button disabled state for mismatched currencies
//
// These exercise the SHARED pure logic in planSelectorLogic.ts — the same
// module PlanSelector.vue delegates to. The predicates are imported, never
// re-implemented, so the test can't drift from the component (the pre-#3824
// tier-based isPlanCurrent silently lingering in a test copy is exactly the
// failure mode this avoids).

import { describe, it, expect } from 'vitest';
import type { Plan as BillingPlan, SubscriptionStatusResponse } from '@/services/billing.service';
import {
  isPlanCurrent,
  isPlanCurrencyMismatch,
  isCurrencyMigrationBlocked,
  isPlanButtonDisabled,
  type PlanButtonState,
} from '@/apps/workspace/billing/planSelectorLogic';

// --- Thin composition of the handler flows under test ---
//
// These mirror the early-return ordering of PlanSelector.vue's async handlers
// (which interleave side effects, so they can't be imported as-is). The
// drift-prone predicates — isPlanCurrent, isPlanCurrencyMismatch — come from
// the shared module, so only the trivial glue (extid/free-tier checks) is local.

/**
 * handlePlanSelect (PlanSelector.vue) bails before any checkout/modal when the
 * org is unset, the plan is already current, the plan is free, or the currency
 * mismatches.
 */
function wouldHandlePlanSelectEarlyReturn(
  plan: BillingPlan,
  orgPlanId: string | undefined,
  orgExtid: string | undefined,
  currentCurrency: string | null
): boolean {
  if (!orgExtid) return true;
  if (isPlanCurrent(plan, orgPlanId)) return true;
  if (plan.tier === 'free') return true;
  return isPlanCurrencyMismatch(currentCurrency, plan);
}

/**
 * handleCompletePendingMigration bails when the org is unset, there's no
 * pending migration, or the still-active subscription's currency conflicts
 * with the migration target.
 */
function wouldCompleteMigrationBail(
  orgExtid: string | undefined,
  pendingMigration: SubscriptionStatusResponse['pending_currency_migration'],
  currentCurrency: string | null
): boolean {
  if (!orgExtid || !pendingMigration) return true;
  return isCurrencyMigrationBlocked(currentCurrency, pendingMigration.target_currency);
}

// --- Test fixtures ---

const createMockPlan = (overrides: Partial<BillingPlan> = {}): BillingPlan => ({
  id: 'identity_plus_v1',
  stripe_price_id: 'price_abc123',
  name: 'Identity Plus',
  tier: 'single_team',
  interval: 'month',
  amount: 1499,
  currency: 'cad',
  region: 'US',
  display_order: 100,
  features: ['Feature 1'],
  limits: { teams: 1 },
  entitlements: ['create_secrets', 'api_access'],
  ...overrides,
});

const createButtonState = (overrides: Partial<PlanButtonState> = {}): PlanButtonState => ({
  orgPlanId: 'free_v1',
  currentCurrency: null,
  isCreatingCheckout: false,
  isReactivating: false,
  isCancelScheduled: false,
  hasActiveSubscription: false,
  ...overrides,
});

const createPendingMigration = (
  overrides: Partial<NonNullable<SubscriptionStatusResponse['pending_currency_migration']>> = {}
): NonNullable<SubscriptionStatusResponse['pending_currency_migration']> => ({
  target_price_id: 'price_eur_456',
  target_plan_name: 'Identity Plus (EU)',
  target_currency: 'eur',
  target_plan_id: 'identity_plus_v1',
  target_interval: 'month',
  effective_after: Math.floor(Date.now() / 1000) + 86400 * 30,
  ...overrides,
});

// --- Tests ---

describe('PlanSelector currency mismatch logic', () => {
  describe('isPlanCurrencyMismatch', () => {
    it('returns true when plan currency differs from current subscription currency', () => {
      const plan = createMockPlan({ currency: 'eur' });
      expect(isPlanCurrencyMismatch('cad', plan)).toBe(true);
    });

    it('returns false when currencies match', () => {
      const plan = createMockPlan({ currency: 'cad' });
      expect(isPlanCurrencyMismatch('cad', plan)).toBe(false);
    });

    it('returns false when current_currency is null (no subscription)', () => {
      const plan = createMockPlan({ currency: 'eur' });
      expect(isPlanCurrencyMismatch(null, plan)).toBe(false);
    });

    it('returns false when current_currency is undefined (via null coalesce)', () => {
      const plan = createMockPlan({ currency: 'eur' });
      // Simulates subscriptionStatus.value?.current_currency ?? null
      expect(isPlanCurrencyMismatch(null, plan)).toBe(false);
    });

    it('returns false when plan currency is empty string', () => {
      const plan = createMockPlan({ currency: '' });
      expect(isPlanCurrencyMismatch('cad', plan)).toBe(false);
    });

    it('is case-sensitive (currencies should be lowercase from API)', () => {
      const plan = createMockPlan({ currency: 'USD' });
      expect(isPlanCurrencyMismatch('cad', plan)).toBe(true);
    });
  });

  describe('handlePlanSelect early return on mismatch', () => {
    it('early-returns when plan currency mismatches subscription currency', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        eurPlan,
        'free_v1', // org's current plan id (not this plan)
        'on1abc123', // org extid
        'cad' // current subscription currency
      );
      expect(result).toBe(true);
    });

    it('does not early-return when currencies match', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        cadPlan,
        'free_v1',
        'on1abc123',
        'cad'
      );
      expect(result).toBe(false);
    });

    it('does not early-return when no current currency (new subscriber)', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        eurPlan,
        'free_v1',
        'on1abc123',
        null
      );
      expect(result).toBe(false);
    });

    it('early-returns for current plan regardless of currency', () => {
      const plan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        plan,
        'identity_plus_v1', // same plan id (this is the current plan)
        'on1abc123',
        'cad'
      );
      expect(result).toBe(true);
    });

    it('early-returns for free tier plans regardless of currency', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free', id: 'free_v1' });
      const result = wouldHandlePlanSelectEarlyReturn(
        freePlan,
        'identity_plus_v1', // org on a paid plan; free card early-returns via free-tier check
        'on1abc123',
        'cad'
      );
      expect(result).toBe(true);
    });

    it('early-returns when no org selected', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      expect(wouldHandlePlanSelectEarlyReturn(cadPlan, 'free_v1', undefined, 'cad')).toBe(true);
    });
  });

  describe('handleCompletePendingMigration currency guard', () => {
    it('bails when current currency differs from migration target currency', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      expect(wouldCompleteMigrationBail('on1abc123', pending, 'cad')).toBe(true);
    });

    it('proceeds when current currency matches migration target', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      expect(wouldCompleteMigrationBail('on1abc123', pending, 'eur')).toBe(false);
    });

    it('proceeds when current currency is null (subscription already cancelled)', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      expect(wouldCompleteMigrationBail('on1abc123', pending, null)).toBe(false);
    });

    it('bails when no org extid', () => {
      const pending = createPendingMigration();
      expect(wouldCompleteMigrationBail(undefined, pending, 'cad')).toBe(true);
    });

    it('bails when no pending migration', () => {
      expect(wouldCompleteMigrationBail('on1abc123', null, 'cad')).toBe(true);
    });

    it('proceeds when pending migration target_currency is empty', () => {
      // Empty target_currency means !!'' is false, so the guard won't trigger,
      // but the checkout will proceed. This is the expected behavior since
      // the API should always provide a target_currency.
      const pending = createPendingMigration({ target_currency: '' });
      expect(wouldCompleteMigrationBail('on1abc123', pending, 'cad')).toBe(false);
    });
  });

  describe('plan card button disabled state', () => {
    it('disables button when plan currency mismatches subscription', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const state = createButtonState({ currentCurrency: 'cad', hasActiveSubscription: true });
      expect(isPlanButtonDisabled(eurPlan, state)).toBe(true);
    });

    it('enables button when currencies match', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const state = createButtonState({ currentCurrency: 'cad', hasActiveSubscription: true });
      expect(isPlanButtonDisabled(cadPlan, state)).toBe(false);
    });

    it('enables button when no current currency (new subscriber)', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const state = createButtonState({ currentCurrency: null });
      expect(isPlanButtonDisabled(eurPlan, state)).toBe(false);
    });

    it('disables button for current plan even when currencies match', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      // Strict id match: org's planid equals this plan's id (#3824)
      const state = createButtonState({
        orgPlanId: 'identity_plus_v1',
        currentCurrency: 'cad',
        hasActiveSubscription: true,
      });
      expect(isPlanButtonDisabled(cadPlan, state)).toBe(true);
    });

    it('enables the current plan button while a cancellation is scheduled (to reactivate)', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const state = createButtonState({
        orgPlanId: 'identity_plus_v1',
        currentCurrency: 'cad',
        hasActiveSubscription: true,
        isCancelScheduled: true,
      });
      expect(isPlanButtonDisabled(cadPlan, state)).toBe(false);
    });

    it('disables button during checkout creation', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const state = createButtonState({
        currentCurrency: 'cad',
        hasActiveSubscription: true,
        isCreatingCheckout: true,
      });
      expect(isPlanButtonDisabled(cadPlan, state)).toBe(true);
    });

    it('disables button while reactivating', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const state = createButtonState({ currentCurrency: 'cad', isReactivating: true });
      expect(isPlanButtonDisabled(cadPlan, state)).toBe(true);
    });

    it('disables the free tier button for a new subscriber (nothing to cancel to)', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free', id: 'free_v1' });
      const state = createButtonState({ orgPlanId: 'free_v1', hasActiveSubscription: false });
      expect(isPlanButtonDisabled(freePlan, state)).toBe(true);
    });

    it('enables the free tier button for an active subscriber (cancel to downgrade)', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free', id: 'free_v1' });
      const state = createButtonState({
        orgPlanId: 'identity_plus_v1',
        hasActiveSubscription: true,
      });
      expect(isPlanButtonDisabled(freePlan, state)).toBe(false);
    });
  });

  describe('cross-region scenarios', () => {
    it('CAD subscriber sees EUR plans as disabled', () => {
      const eurPlan = createMockPlan({ currency: 'eur', region: 'EU' });
      const state = createButtonState({ currentCurrency: 'cad', hasActiveSubscription: true });
      expect(isPlanCurrencyMismatch('cad', eurPlan)).toBe(true);
      expect(isPlanButtonDisabled(eurPlan, state)).toBe(true);
    });

    it('EUR subscriber sees CAD plans as disabled', () => {
      const cadPlan = createMockPlan({ currency: 'cad', region: 'US' });
      const state = createButtonState({ currentCurrency: 'eur', hasActiveSubscription: true });
      expect(isPlanCurrencyMismatch('eur', cadPlan)).toBe(true);
      expect(isPlanButtonDisabled(cadPlan, state)).toBe(true);
    });

    it('new subscriber (no currency) sees paid plans as enabled', () => {
      const cadPlan = createMockPlan({ currency: 'cad', region: 'US' });
      const eurPlan = createMockPlan({ currency: 'eur', region: 'EU' });

      expect(isPlanCurrencyMismatch(null, cadPlan)).toBe(false);
      expect(isPlanCurrencyMismatch(null, eurPlan)).toBe(false);
    });

    it('pending migration blocked when old CAD sub still active for EUR target', () => {
      const pending = createPendingMigration({
        target_currency: 'eur',
        target_plan_name: 'Identity Plus (EU)',
      });
      // Old subscription still active with CAD
      expect(wouldCompleteMigrationBail('on1abc123', pending, 'cad')).toBe(true);
    });

    it('pending migration allowed after old sub cancels (currency becomes null)', () => {
      const pending = createPendingMigration({
        target_currency: 'eur',
        target_plan_name: 'Identity Plus (EU)',
      });
      // Old subscription cancelled — current_currency is null
      expect(wouldCompleteMigrationBail('on1abc123', pending, null)).toBe(false);
    });
  });
});
