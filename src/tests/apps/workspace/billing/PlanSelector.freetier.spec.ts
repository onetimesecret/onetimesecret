// src/tests/apps/workspace/billing/PlanSelector.freetier.spec.ts

//
// MOUNTED tests for the Free card in the authenticated plan-change grid.
//
// Why a separate file from PlanSelector.spec.ts / PlanSelector.currency.spec.ts:
// both of those are pure-logic specs that deliberately never mount the
// component ("to avoid complex Vue/Pinia/i18n setup"). The module mocks needed
// to mount are file-scoped and would apply to every pure-logic test in those
// files. Predicate-level coverage stays there; this file covers only what
// requires a real render.
//
// Context: GET /billing/api/plans used to drop every price-less plan, so
// free_v1 (defined with `prices: []`) never reached the frontend. Now that the
// endpoint emits a synthetic free record, PlanSelector's default
// `freePlanStandalone: false` puts a Free card in the authenticated grid for
// the first time. That is intended — planSelectorLogic has purpose-built
// free-tier branches and PlanSelector.vue:728 has free-specific card ordering —
// so these tests pin the rendered behavior of a surface that was dead code.
//

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import { nextTick, ref } from 'vue';
import PlanSelector from '@/apps/workspace/billing/PlanSelector.vue';
import { createTestI18n } from '@tests/setup';
import { mockPlans } from '@/tests/fixtures/billing.fixture';
import type { Plan as BillingPlan, SubscriptionStatusResponse } from '@/services/billing.service';

// --- Route: extid is required or onMounted skips the org + subscription load
// entirely, leaving selectedOrg null and every assertion below vacuous.
vi.mock('vue-router', () => ({
  useRoute: () => ({
    path: '/billing/on1abc123/plans',
    params: { extid: 'on1abc123' },
    query: {},
  }),
}));

// --- Presentational stubs. PlanCard is deliberately NOT stubbed: its
// data-testid, Current badge and disabled button are what we assert on.
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: {
    name: 'OIcon',
    template: '<span class="o-icon" />',
    props: ['collection', 'name', 'class'],
  },
}));
vi.mock('@/shared/components/layout/BillingLayout.vue', () => ({
  default: { name: 'BillingLayout', template: '<div class="billing-layout"><slot /></div>' },
}));
vi.mock('@/shared/components/billing/PlanCardSkeleton.vue', () => ({
  default: { name: 'PlanCardSkeleton', template: '<div class="plan-card-skeleton" />' },
}));
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: {
    name: 'BasicFormAlerts',
    template: '<div class="form-alerts">{{ error }}</div>',
    props: ['error'],
  },
}));
vi.mock('@/shared/components/ui/FeedbackToggle.vue', () => ({
  default: { name: 'FeedbackToggle', template: '<button class="feedback-toggle" />' },
}));

// --- Modals: stubbed so `open` is inspectable as a prop.
vi.mock('@/apps/workspace/billing/PlanChangeModal.vue', () => ({
  default: {
    name: 'PlanChangeModal',
    template: '<div class="plan-change-modal" />',
    props: ['open', 'orgExtId', 'currentPlan', 'targetPlan'],
  },
}));
vi.mock('@/apps/workspace/billing/CancelSubscriptionModal.vue', () => ({
  default: {
    name: 'CancelSubscriptionModal',
    template: '<div class="cancel-subscription-modal" />',
    props: ['open', 'orgExtId', 'planName', 'periodEnd'],
  },
}));
vi.mock('@/apps/workspace/billing/CurrencyMigrationModal.vue', () => ({
  default: {
    name: 'CurrencyMigrationModal',
    template: '<div class="currency-migration-modal" />',
    props: ['open', 'orgExtId', 'conflict'],
  },
}));
vi.mock('@/apps/workspace/billing/PendingMigrationBanner.vue', () => ({
  default: {
    name: 'PendingMigrationBanner',
    template: '<div class="pending-migration-banner" />',
    props: ['targetPlanName', 'targetCurrency', 'effectiveDate', 'isCompletingMigration'],
  },
}));

// --- Services. extractCurrencyConflict is a NAMED import in PlanSelector.vue,
// and formatCurrency is called unconditionally by PlanCard.
const mockListPlans = vi.fn();
const mockGetSubscriptionStatus = vi.fn();
const mockCreateCheckoutSession = vi.fn();
const mockReactivateSubscription = vi.fn();
vi.mock('@/services/billing.service', () => ({
  BillingService: {
    listPlans: (...args: unknown[]) => mockListPlans(...args),
    getSubscriptionStatus: (...args: unknown[]) => mockGetSubscriptionStatus(...args),
    createCheckoutSession: (...args: unknown[]) => mockCreateCheckoutSession(...args),
    reactivateSubscription: (...args: unknown[]) => mockReactivateSubscription(...args),
  },
  extractCurrencyConflict: () => null,
}));

vi.mock('@/types/billing', () => ({
  formatCurrency: (amount: number, currency = 'cad') =>
    `${currency.toUpperCase()} ${(amount / 100).toFixed(2)}`,
  isLegacyPlan: (planId: string) => planId === 'identity',
  getPlanLabel: (planId: string) => planId,
}));

// PlanCard imports the locale-aware wrapper (#4048); mock it the same way so
// assertions stay locale-independent.
vi.mock('@/utils/format/currency', () => ({
  formatCurrency: (amount: number, currency = 'cad') =>
    `${currency.toUpperCase()} ${(amount / 100).toFixed(2)}`,
  activeIntlLocale: () => undefined,
}));

vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({
    message: err instanceof Error ? err.message : 'Unknown error',
  }),
}));

vi.mock('@/services/diagnostics.service', () => ({
  captureMessage: vi.fn(),
  isDiagnosticsEnabled: () => false,
}));

// --- Org store
const mockFetchOrganization = vi.fn();
vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    fetchOrganization: mockFetchOrganization,
  }),
}));

// --- Entitlements. isLoadingDefinitions gates isLoadingContent, which gates the
// ENTIRE render behind PlanCardSkeleton — it must be a resolved ref(false).
const mockInitDefinitions = vi.fn();
const mockIsLoadingDefinitions = ref(false);
const mockDefinitionsError = ref('');
vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    initDefinitions: mockInitDefinitions,
    isLoadingDefinitions: mockIsLoadingDefinitions,
    definitionsError: mockDefinitionsError,
  }),
}));

// --- Fixtures ---

// The grid as the wire now delivers it: the synthetic free record plus two paid
// monthly plans. mockPlans.free is the fixture pinned to the API contract.
const gridPlans: BillingPlan[] = [
  mockPlans.free,
  mockPlans.single_team, // identity_plus_v1, tier single_account, cad
  mockPlans.multi_team, // team_plus_v1, tier single_team, cad
];

interface MockOrg {
  objid: string;
  extid: string;
  display_name: string;
  planid: string;
  entitlements: string[];
  limits: Record<string, number>;
}

const makeOrg = (planid: string): MockOrg => ({
  objid: 'org_123',
  extid: 'on1abc123',
  display_name: 'Test Organization',
  planid,
  entitlements: [],
  limits: {},
});

const makeSubscription = (
  overrides: Partial<SubscriptionStatusResponse> = {}
): SubscriptionStatusResponse => ({
  has_active_subscription: true,
  current_plan: 'identity_plus_v1',
  current_price_id: 'price_single_monthly',
  subscription_status: 'active',
  current_currency: 'cad',
  cancel_at_period_end: false,
  ...overrides,
});

const FREE_CARD = '[data-testid="plan-card-free_v1"]';
const FREE_BUTTON = '[data-testid="plan-select-free_v1"]';
const PAID_CARD = '[data-testid="plan-card-identity_plus_v1"]';
const PAID_BUTTON = '[data-testid="plan-select-identity_plus_v1"]';

describe('PlanSelector — free card in the authenticated grid', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;
  const i18n = createTestI18n();

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    mockIsLoadingDefinitions.value = false;
    mockDefinitionsError.value = '';
    mockInitDefinitions.mockResolvedValue(undefined);
    mockListPlans.mockResolvedValue({ plans: gridPlans });
  });

  afterEach(() => {
    wrapper?.unmount();
  });

  const mountComponent = async (
    options: {
      planid?: string;
      subscription?: SubscriptionStatusResponse | null;
    } = {}
  ) => {
    mockFetchOrganization.mockResolvedValue(makeOrg(options.planid ?? 'identity_plus_v1'));
    if (options.subscription === null) {
      mockGetSubscriptionStatus.mockRejectedValue(new Error('no subscription'));
    } else {
      mockGetSubscriptionStatus.mockResolvedValue(options.subscription ?? makeSubscription());
    }

    wrapper = mount(PlanSelector, {
      global: { plugins: [i18n, pinia] },
    });
    await flushPromises();
    await nextTick();
    return wrapper;
  };

  // ============================================================
  // Rendering
  // ============================================================
  describe('rendering', () => {
    it('renders exactly one Free card in the grid (default freePlanStandalone: false)', async () => {
      await mountComponent();

      expect(wrapper.findAll(FREE_CARD)).toHaveLength(1);
      // The standalone banner branch must NOT be taken. Note it is a v-else-if
      // in the same chain as the grid, so if it ever fired the grid would
      // vanish — asserting the paid cards are present covers both.
      expect(wrapper.find(PAID_CARD).exists()).toBe(true);
      expect(wrapper.text()).not.toContain('web.pricing.free_tier_description');
    });

    it('keeps the Free card out of the interval filter (renders in the yearly view too)', async () => {
      await mountComponent();

      await wrapper.find('[data-testid="billing-interval-year"]').trigger('click');
      await nextTick();

      // Paid monthly cards drop out; the single free record stays, once.
      expect(wrapper.findAll(FREE_CARD)).toHaveLength(1);
      expect(wrapper.find(PAID_CARD).exists()).toBe(false);
    });
  });

  // ============================================================
  // Button state
  // ============================================================
  describe('button state', () => {
    it('disables the Free card for a customer with no active subscription', async () => {
      await mountComponent({ planid: 'free_v1', subscription: null });

      const button = wrapper.find(FREE_BUTTON);
      expect(button.exists()).toBe(true);
      expect(button.attributes('disabled')).toBeDefined();
    });

    it('enables the Free card and labels it "cancel to downgrade" for an active subscriber', async () => {
      await mountComponent({ planid: 'identity_plus_v1', subscription: makeSubscription() });

      const button = wrapper.find(FREE_BUTTON);
      expect(button.attributes('disabled')).toBeUndefined();
      // canDowngrade resolves only because the org's planid is present in the
      // plans list (identity_plus_v1 → single_account, rank 1 > free rank 0).
      expect(button.text()).toBe('web.billing.plans.cancel_to_downgrade');
    });

    it('opens the cancel modal when an active subscriber clicks the Free card', async () => {
      await mountComponent({ planid: 'identity_plus_v1', subscription: makeSubscription() });

      const modal = wrapper.findComponent({ name: 'CancelSubscriptionModal' });
      expect(modal.props('open')).toBe(false);

      await wrapper.find(FREE_BUTTON).trigger('click');
      await nextTick();

      expect(modal.props('open')).toBe(true);
    });
  });

  // ============================================================
  // Current badge
  // ============================================================
  describe('current badge', () => {
    it('lands the Current badge on the Free card when org.planid is free_v1', async () => {
      await mountComponent({ planid: 'free_v1', subscription: null });

      expect(wrapper.find(FREE_CARD).text()).toContain('web.billing.plans.current_badge');
      expect(wrapper.find(PAID_CARD).text()).not.toContain('web.billing.plans.current_badge');
    });

    it('does not badge the Free card for a paid subscriber', async () => {
      await mountComponent({ planid: 'identity_plus_v1', subscription: makeSubscription() });

      expect(wrapper.find(FREE_CARD).text()).not.toContain('web.billing.plans.current_badge');
      expect(wrapper.find(PAID_CARD).text()).toContain('web.billing.plans.current_badge');
    });
  });

  // ============================================================
  // Currency regression
  // ============================================================
  describe('subscriber on a non-default currency', () => {
    // The synthetic free record carries the deployment default currency ('cad'
    // in these fixtures). A subscriber whose subscription currency differs is a
    // real state — see the pending-currency-migration flow. Before the free-tier
    // exemption in isPlanCurrencyMismatch, isPlanButtonDisabled (which ORs the
    // currency predicate in with no free-tier ordering protection) rendered the
    // Free card permanently disabled with a misleading "region mismatch"
    // reason, making downgrade-to-free unreachable from the grid.
    const eurSubscriber = () => makeSubscription({ current_currency: 'eur' });

    it('leaves the Free card actionable and free of a region-mismatch reason', async () => {
      await mountComponent({ planid: 'identity_plus_v1', subscription: eurSubscriber() });

      const card = wrapper.find(FREE_CARD);
      expect(wrapper.find(FREE_BUTTON).attributes('disabled')).toBeUndefined();
      expect(card.text()).not.toContain('web.billing.plan_unavailable_region_mismatch');
      expect(wrapper.find(FREE_BUTTON).text()).toBe('web.billing.plans.cancel_to_downgrade');
    });

    it('still opens the cancel modal on click', async () => {
      await mountComponent({ planid: 'identity_plus_v1', subscription: eurSubscriber() });

      await wrapper.find(FREE_BUTTON).trigger('click');
      await nextTick();

      expect(wrapper.findComponent({ name: 'CancelSubscriptionModal' }).props('open')).toBe(true);
    });

    it('still blocks PAID cards with the region-mismatch reason (exemption is tier-scoped)', async () => {
      // Control: the exemption must not disarm the currency guard generally.
      // team_plus_v1 is a different plan than the org's, priced in cad.
      await mountComponent({ planid: 'identity_plus_v1', subscription: eurSubscriber() });

      const paidButton = wrapper.find('[data-testid="plan-select-team_plus_v1"]');
      expect(paidButton.attributes('disabled')).toBeDefined();
      expect(wrapper.find('[data-testid="plan-card-team_plus_v1"]').text()).toContain(
        'web.billing.plan_unavailable_region_mismatch'
      );
      // The org's own card is disabled for being current, not for currency.
      expect(wrapper.find(PAID_BUTTON).attributes('disabled')).toBeDefined();
    });
  });
});
