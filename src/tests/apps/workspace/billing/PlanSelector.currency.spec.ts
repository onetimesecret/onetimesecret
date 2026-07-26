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
  isPlanCurrencyMismatch,
  isPlanButtonDisabled,
  resolvePlanSelectAction,
  resolveCompletePendingMigrationAction,
  type PlanButtonState,
  type PlanSelectContext,
  type CompletePendingMigrationContext,
} from '@/apps/workspace/billing/planSelectorLogic';

// The handler-flow tests below assert the ACTUAL decision functions
// PlanSelector.vue calls (resolvePlanSelectAction /
// resolveCompletePendingMigrationAction) rather than re-implementing the
// early-return ordering. If the component reorders a guard, these break — the
// drift the previous hand-copied helpers couldn't catch (#3824).

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

// Default context: org present, on the free plan, no subscription — i.e. a new
// subscriber. Override per-test to exercise the other handlePlanSelect branches.
const createSelectContext = (overrides: Partial<PlanSelectContext> = {}): PlanSelectContext => ({
  orgExtid: 'on1abc123',
  orgPlanId: 'free_v1',
  currentCurrency: null,
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

// Migration guard context — org always present; the no-org case is inlined.
const migCtx = (currentCurrency: string | null): CompletePendingMigrationContext => ({
  orgExtid: 'on1abc123',
  currentCurrency,
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

  describe('resolvePlanSelectAction (handlePlanSelect decision)', () => {
    it('is currency-blocked when plan currency mismatches subscription currency', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const action = resolvePlanSelectAction(
        eurPlan,
        createSelectContext({ orgPlanId: 'free_v1', currentCurrency: 'cad' })
      );
      expect(action).toBe('currency-blocked');
    });

    it('proceeds to checkout when currencies match and no active subscription', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const action = resolvePlanSelectAction(
        cadPlan,
        createSelectContext({ orgPlanId: 'free_v1', currentCurrency: 'cad' })
      );
      expect(action).toBe('checkout');
    });

    it('proceeds to checkout when no current currency (new subscriber)', () => {
      const eurPlan = createMockPlan({ currency: 'eur', tier: 'single_team' });
      const action = resolvePlanSelectAction(
        eurPlan,
        createSelectContext({ orgPlanId: 'free_v1', currentCurrency: null })
      );
      expect(action).toBe('checkout');
    });

    it('opens the plan-change modal for an active subscriber switching paid plans', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const action = resolvePlanSelectAction(
        cadPlan,
        createSelectContext({
          orgPlanId: 'team_plus_v1', // different paid plan than this card
          currentCurrency: 'cad',
          hasActiveSubscription: true,
        })
      );
      expect(action).toBe('open-plan-change-modal');
    });

    it('is a no-op for the current plan (not cancel-scheduled) regardless of currency', () => {
      const plan = createMockPlan({ currency: 'cad', tier: 'single_team' }); // id identity_plus_v1
      const action = resolvePlanSelectAction(
        plan,
        createSelectContext({ orgPlanId: 'identity_plus_v1', currentCurrency: 'cad' })
      );
      expect(action).toBe('noop');
    });

    it('reactivates when the current plan is clicked while a cancellation is scheduled', () => {
      const plan = createMockPlan({ currency: 'cad', tier: 'single_team' }); // id identity_plus_v1
      const action = resolvePlanSelectAction(
        plan,
        createSelectContext({
          orgPlanId: 'identity_plus_v1',
          currentCurrency: 'cad',
          isCancelScheduled: true,
        })
      );
      expect(action).toBe('reactivate');
    });

    it('opens the cancel modal for a free card when the subscriber is active', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free', id: 'free_v1' });
      const action = resolvePlanSelectAction(
        freePlan,
        createSelectContext({ orgPlanId: 'identity_plus_v1', hasActiveSubscription: true })
      );
      expect(action).toBe('open-cancel-modal');
    });

    it('is a no-op for a free card when there is no active subscription', () => {
      const freePlan = createMockPlan({ currency: 'cad', tier: 'free', id: 'free_v1' });
      const action = resolvePlanSelectAction(
        freePlan,
        createSelectContext({ orgPlanId: 'free_v1', hasActiveSubscription: false })
      );
      expect(action).toBe('noop');
    });

    it('is a no-op when no org is selected', () => {
      const cadPlan = createMockPlan({ currency: 'cad', tier: 'single_team' });
      const action = resolvePlanSelectAction(
        cadPlan,
        createSelectContext({ orgExtid: undefined, currentCurrency: 'cad' })
      );
      expect(action).toBe('noop');
    });
  });

  describe('resolveCompletePendingMigrationAction (migration guard)', () => {
    it('is currency-blocked when current currency differs from migration target', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      expect(resolveCompletePendingMigrationAction(pending, migCtx('cad'))).toBe('currency-blocked');
    });

    it('proceeds to checkout when current currency matches migration target', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      expect(resolveCompletePendingMigrationAction(pending, migCtx('eur'))).toBe('checkout');
    });

    it('proceeds to checkout when current currency is null (subscription already cancelled)', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      expect(resolveCompletePendingMigrationAction(pending, migCtx(null))).toBe('checkout');
    });

    it('is a no-op when no org extid', () => {
      const pending = createPendingMigration();
      // Inline (not migCtx) because an explicit undefined still hits the default.
      const ctx: CompletePendingMigrationContext = { orgExtid: undefined, currentCurrency: 'cad' };
      expect(resolveCompletePendingMigrationAction(pending, ctx)).toBe('noop');
    });

    it('is a no-op when no pending migration', () => {
      expect(resolveCompletePendingMigrationAction(null, migCtx('cad'))).toBe('noop');
    });

    it('proceeds to checkout when pending migration target_currency is empty', () => {
      // Empty target_currency means !!'' is false, so the guard won't trigger,
      // but the checkout will proceed. The API should always provide a currency.
      const pending = createPendingMigration({ target_currency: '' });
      expect(resolveCompletePendingMigrationAction(pending, migCtx('cad'))).toBe('checkout');
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
      const pending = createPendingMigration({ target_currency: 'eur' });
      // Old subscription still active with CAD
      expect(resolveCompletePendingMigrationAction(pending, migCtx('cad'))).toBe('currency-blocked');
    });

    it('pending migration allowed after old sub cancels (currency becomes null)', () => {
      const pending = createPendingMigration({ target_currency: 'eur' });
      // Old subscription cancelled — current_currency is null
      expect(resolveCompletePendingMigrationAction(pending, migCtx(null))).toBe('checkout');
    });
  });
});
