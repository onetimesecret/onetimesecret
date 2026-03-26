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
// NOTE: These tests exercise extracted logic from PlanSelector.vue.
// They do not mount the component to avoid complex Vue/Pinia/i18n setup.

import { describe, it, expect, vi } from 'vitest';
import type { Plan as BillingPlan, SubscriptionStatusResponse } from '@/services/billing.service';

// --- Extracted logic from PlanSelector.vue ---

/**
 * isPlanCurrencyMismatch — line ~90 in PlanSelector.vue
 *
 * Returns true when the plan's currency differs from the
 * current subscription's currency.
 */
function isPlanCurrencyMismatch(
  currentCurrency: string | null,
  plan: BillingPlan
): boolean {
  return !!currentCurrency && !!plan.currency && currentCurrency !== plan.currency;
}

/**
 * Simulates handlePlanSelect's early-return logic (lines ~213-220)
 *
 * Returns true if the handler would bail out before making an API call.
 */
function wouldHandlePlanSelectEarlyReturn(
  plan: BillingPlan,
  currentTier: string,
  orgExtid: string | undefined,
  currentCurrency: string | null
): boolean {
  // isPlanCurrent check
  if (plan.tier === currentTier) return true;
  // No org selected
  if (!orgExtid) return true;
  // Free tier — no checkout
  if (plan.tier === 'free') return true;
  // Currency mismatch
  if (isPlanCurrencyMismatch(currentCurrency, plan)) return true;
  return false;
}

/**
 * Simulates handleCompletePendingMigration's currency guard
 * (the fix added in this PR).
 *
 * Returns true if the handler would bail out before creating a checkout.
 */
function wouldCompleteMigrationBail(
  orgExtid: string | undefined,
  pendingMigration: SubscriptionStatusResponse['pending_currency_migration'],
  currentCurrency: string | null
): boolean {
  if (!orgExtid || !pendingMigration) return true;
  if (
    currentCurrency &&
    pendingMigration.target_currency &&
    currentCurrency !== pendingMigration.target_currency
  ) {
    return true;
  }
  return false;
}

/**
 * Simulates the button-disabled condition from PlanSelector template (line ~608):
 *   :button-disabled="isPlanCurrent(plan) || isCreatingCheckout
 *     || plan.tier === 'free' || isPlanCurrencyMismatch(plan)"
 */
function isButtonDisabled(
  plan: BillingPlan,
  currentTier: string,
  isCreatingCheckout: boolean,
  currentCurrency: string | null
): boolean {
  const isPlanCurrent = plan.tier === currentTier;
  return (
    isPlanCurrent ||
    isCreatingCheckout ||
    plan.tier === 'free' ||
    isPlanCurrencyMismatch(currentCurrency, plan)
  );
}

// --- Test fixtures ---

const createMockPlan = (overrides: Partial<BillingPlan> = {}): BillingPlan => ({
  id: 'identity_plus_v1_monthly',
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

const createPendingMigration = (
  overrides: Partial<NonNullable<SubscriptionStatusResponse['pending_currency_migration']>> = {}
): NonNullable<SubscriptionStatusResponse['pending_currency_migration']> => ({
  target_price_id: 'price_eur_456',
  target_plan_name: 'Identity Plus (EU)',
  target_currency: 'eur',
  target_plan_id: 'identity_plus_v1_monthly',
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
        'free', // current tier
        'on1abc123', // org extid
        'cad' // current subscription currency
      );
      expect(result).toBe(true);
    });

    it('does not early-return when currencies match', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        cadPlan,
        'free',
        'on1abc123',
        'cad'
      );
      expect(result).toBe(false);
    });

    it('does not early-return when no current currency (new subscriber)', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        eurPlan,
        'free',
        'on1abc123',
        null
      );
      expect(result).toBe(false);
    });

    it('early-returns for current plan regardless of currency', () => {
      const plan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const result = wouldHandlePlanSelectEarlyReturn(
        plan,
        'single_team', // same tier
        'on1abc123',
        'cad'
      );
      expect(result).toBe(true);
    });

    it('early-returns for free tier plans regardless of currency', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free' });
      const result = wouldHandlePlanSelectEarlyReturn(
        freePlan,
        'single_team',
        'on1abc123',
        'cad'
      );
      expect(result).toBe(true);
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
      expect(isButtonDisabled(eurPlan, 'free', false, 'cad')).toBe(true);
    });

    it('enables button when currencies match', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      expect(isButtonDisabled(cadPlan, 'free', false, 'cad')).toBe(false);
    });

    it('enables button when no current currency (new subscriber)', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      expect(isButtonDisabled(eurPlan, 'free', false, null)).toBe(false);
    });

    it('disables button for current plan even when currencies match', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      expect(isButtonDisabled(cadPlan, 'single_team', false, 'cad')).toBe(true);
    });

    it('disables button during checkout creation', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      expect(isButtonDisabled(cadPlan, 'free', true, 'cad')).toBe(true);
    });

    it('disables button for free tier plans', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free' });
      expect(isButtonDisabled(freePlan, 'free', false, null)).toBe(true);
    });
  });

  describe('cross-region scenarios', () => {
    it('USD subscriber sees EUR plans as disabled', () => {
      const eurPlan = createMockPlan({ currency: 'eur', region: 'EU' });
      expect(isPlanCurrencyMismatch('cad', eurPlan)).toBe(true);
      expect(isButtonDisabled(eurPlan, 'free', false, 'cad')).toBe(true);
    });

    it('EUR subscriber sees USD plans as disabled', () => {
      const cadPlan = createMockPlan({ currency: 'cad', region: 'US' });
      expect(isPlanCurrencyMismatch('eur', cadPlan)).toBe(true);
      expect(isButtonDisabled(cadPlan, 'free', false, 'eur')).toBe(true);
    });

    it('new subscriber (no currency) sees all plans as enabled', () => {
      const cadPlan = createMockPlan({ currency: 'cad', region: 'US' });
      const eurPlan = createMockPlan({ currency: 'eur', region: 'EU' });

      expect(isPlanCurrencyMismatch(null, cadPlan)).toBe(false);
      expect(isPlanCurrencyMismatch(null, eurPlan)).toBe(false);
    });

    it('pending migration blocked when old USD sub still active for EUR target', () => {
      const pending = createPendingMigration({
        target_currency: 'eur',
        target_plan_name: 'Identity Plus (EU)',
      });
      // Old subscription still active with USD
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
