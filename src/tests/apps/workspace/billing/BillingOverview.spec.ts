// src/tests/apps/workspace/billing/BillingOverview.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createI18n } from 'vue-i18n';
import { createPinia, setActivePinia } from 'pinia';
import BillingOverview from '@/apps/workspace/billing/BillingOverview.vue';
import { nextTick, ref } from 'vue';
import {
  createMockOverviewResponse,
  mockOverviewResponses,
} from '@/tests/fixtures/billing.fixture';

vi.mock('vue-router', () => ({ useRoute: () => ({ path: '/billing/overview' }) }));
vi.mock('@/shared/components/icons/OIcon.vue', () => ({
  default: { name: 'OIcon', template: '<span class="o-icon" />', props: ['collection', 'name', 'class'] },
}));
vi.mock('@/shared/components/layout/BillingLayout.vue', () => ({
  default: { name: 'BillingLayout', template: '<div class="billing-layout"><slot /></div>' },
}));
vi.mock('@/shared/components/forms/BasicFormAlerts.vue', () => ({
  default: { name: 'BasicFormAlerts', template: '<div class="form-alerts">{{ error }}</div>', props: ['error'] },
}));

const mockGetOverview = vi.fn();
vi.mock('@/services/billing.service', () => ({
  BillingService: { getOverview: (...args: unknown[]) => mockGetOverview(...args) },
}));

// Lightweight org shape for store mock (not full Organization type)
const mockOrganization = {
  id: 'org_123', extid: 'on1abc123', display_name: 'Test Organization',
  planid: 'identity_plus_v1_monthly', entitlements: ['api_access'], limits: { teams: 1 }, is_default: true,
};
const mockFreeOrganization = {
  id: 'org_456', extid: 'on2def456', display_name: 'Free Org',
  planid: '', entitlements: [] as string[], limits: { teams: 0 }, is_default: false,
};

type MockOrg = typeof mockOrganization;
const storeState = { organizations: [] as MockOrg[] };
const mockFetchOrganizations = vi.fn();
const mockFetchOrganization = vi.fn();
const mockFetchEntitlements = vi.fn();

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    get organizations() { return storeState.organizations; },
    fetchOrganizations: mockFetchOrganizations,
    fetchOrganization: mockFetchOrganization,
    fetchEntitlements: mockFetchEntitlements,
  }),
}));

const mockEntitlements = ref<string[]>([]);
const mockInitDefinitions = vi.fn();
vi.mock('@/shared/composables/useEntitlements', () => ({
  useEntitlements: () => ({
    entitlements: mockEntitlements,
    formatEntitlement: (key: string) => `Formatted: ${key}`,
    initDefinitions: mockInitDefinitions,
  }),
}));

vi.mock('@/schemas/errors', () => ({
  classifyError: (err: unknown) => ({ message: err instanceof Error ? err.message : 'Unknown error' }),
}));
vi.mock('@/types/billing', () => ({
  getPlanDisplayName: (id: string) => ({ identity_plus_v1_monthly: 'Identity Plus' }[id] || id),
}));

// Use shared fixture factory for overview response
const defaultOverviewResponse = createMockOverviewResponse({
  organization: { id: 'org_123', external_id: 'on1abc123', display_name: 'Test Org', billing_email: null },
});

const i18n = createI18n({
  legacy: false, locale: 'en',
  messages: { en: { web: {
    billing: {
      overview: { title: 'Billing Overview', organization_selector: 'Select Organization', current_plan: 'Current Plan',
        upgrade_plan: 'Upgrade Plan', change_plan: 'Change Plan', plan_features: 'Plan Features',
        no_organizations_title: 'No Organizations', no_organizations_description: 'Create an organization to get started',
        no_entitlements: 'No entitlements available', next_billing_date: 'Next Billing Date',
        days_remaining: 'days remaining' },
      subscription: { active: 'Active' }, plans: { free_plan: 'Free' },
      features: { feature1: 'Feature One', feature2: 'Feature Two' },
    },
    organizations: { create_organization: 'Create Organization' }, COMMON: { loading: 'Loading...' },
  }}},
});

const routerLinkStub = { template: '<a class="router-link"><slot /></a>', props: ['to'] };

describe('BillingOverview', () => {
  let wrapper: VueWrapper;
  let pinia: ReturnType<typeof createPinia>;

  beforeEach(() => {
    pinia = createPinia();
    setActivePinia(pinia);
    vi.clearAllMocks();
    storeState.organizations = [];
    mockEntitlements.value = [];
    mockInitDefinitions.mockResolvedValue(undefined);
    mockFetchEntitlements.mockResolvedValue(undefined);
    mockGetOverview.mockResolvedValue(defaultOverviewResponse);
  });

  afterEach(() => { wrapper?.unmount(); });

  const mountComponent = async (options: { organizations?: MockOrg[] } = {}) => {
    const orgs = options.organizations ?? [mockOrganization];
    storeState.organizations = orgs;
    mockFetchOrganization.mockImplementation(
      async (extid: string) => orgs.find(o => o.extid === extid) || orgs[0]
    );
    mockFetchOrganizations.mockImplementation(async () => {
      storeState.organizations = orgs;
      return orgs;
    });

    const component = mount(BillingOverview, {
      global: { plugins: [i18n, pinia], stubs: { RouterLink: routerLinkStub } },
    });
    await flushPromises();
    await nextTick();
    return component;
  };

  describe('Loading State', () => {
    it('renders loading state initially', async () => {
      storeState.organizations = [mockOrganization];
      let resolveOrg: (value: MockOrg) => void;
      mockFetchOrganization.mockReturnValue(new Promise(r => { resolveOrg = r; }));

      wrapper = mount(BillingOverview, {
        global: { plugins: [i18n, pinia], stubs: { RouterLink: routerLinkStub } },
      });
      expect(wrapper.find('.billing-layout').exists()).toBe(true);

      resolveOrg!(mockOrganization);
      await flushPromises();
      expect(wrapper.text()).toContain('Billing Overview');
    });
  });

  describe('Plan Display', () => {
    it('displays current plan name', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Identity Plus');
    });

    it('shows "Free" for users without subscription', async () => {
      mockGetOverview.mockResolvedValueOnce(mockOverviewResponses.free);
      wrapper = await mountComponent({ organizations: [mockFreeOrganization] });
      expect(wrapper.text()).toContain('Free');
    });
  });

  describe('Entitlements Display', () => {
    it('renders entitlements list from plan features', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Feature One');
      expect(wrapper.text()).toContain('Feature Two');
    });

    it('shows entitlements loading skeleton during load', async () => {
      let resolveOverview: (value: ReturnType<typeof createMockOverviewResponse>) => void;
      storeState.organizations = [mockOrganization];
      mockFetchOrganization.mockResolvedValue(mockOrganization);
      mockFetchEntitlements.mockResolvedValue(undefined);
      mockGetOverview.mockImplementationOnce(() => new Promise(r => { resolveOverview = r; }));

      wrapper = mount(BillingOverview, {
        global: { plugins: [i18n, pinia], stubs: { RouterLink: routerLinkStub } },
      });

      await nextTick();
      await nextTick();
      expect(wrapper.find('.billing-layout').exists()).toBe(true);

      resolveOverview!(defaultOverviewResponse);
      await flushPromises();
      expect(wrapper.text()).toContain('Feature One');
    });

    it('handles entitlements API error gracefully', async () => {
      mockGetOverview.mockRejectedValueOnce(new Error('Failed to load billing'));
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Failed to load billing');
      expect(wrapper.find('.billing-layout').exists()).toBe(true);
    });
  });

  describe('Multi-Org Support', () => {
    it('multi-org selector triggers data reload on change', async () => {
      const orgs = [mockOrganization, mockFreeOrganization];
      wrapper = await mountComponent({ organizations: orgs });

      const selector = wrapper.find('#org-select');
      expect(selector.exists()).toBe(true);
      expect(mockGetOverview).toHaveBeenCalledWith('on1abc123');

      await selector.setValue('org_456');
      await flushPromises();
      expect(mockGetOverview).toHaveBeenCalledWith('on2def456');
    });

    it('hides org selector for single organization', async () => {
      wrapper = await mountComponent({ organizations: [mockOrganization] });
      expect(wrapper.find('#org-select').exists()).toBe(false);
    });
  });

  describe('Action Buttons', () => {
    it('shows "Change Plan" button for subscribers', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Change Plan');
    });

    it('shows "Upgrade Plan" button for free users', async () => {
      mockGetOverview.mockResolvedValueOnce(mockOverviewResponses.free);
      wrapper = await mountComponent({ organizations: [mockFreeOrganization] });
      expect(wrapper.text()).toContain('Upgrade Plan');
    });
  });

  describe('Empty State', () => {
    it('shows empty state when no organizations', async () => {
      wrapper = await mountComponent({ organizations: [] });
      expect(wrapper.text()).toContain('No Organizations');
      expect(wrapper.find('a').exists()).toBe(true);
    });
  });

  describe('Next Billing Date', () => {
    it('displays next billing date when subscription has period_end', async () => {
      wrapper = await mountComponent();
      const billingDateEl = wrapper.find('[data-testid="next-billing-date"]');
      expect(billingDateEl.exists()).toBe(true);
      expect(billingDateEl.text()).toContain('Next Billing Date');

      const expectedDate = new Date(defaultOverviewResponse.subscription!.period_end * 1000);
      const formattedDate = new Intl.DateTimeFormat('en-US', {
        month: 'long', day: 'numeric', year: 'numeric',
      }).format(expectedDate);
      expect(billingDateEl.text()).toContain(formattedDate);
    });

    it('does not display next billing date when subscription has no period_end', async () => {
      const noDateResponse = createMockOverviewResponse({
        organization: { id: 'org_123', external_id: 'on1abc123', display_name: 'Test Org', billing_email: null },
        subscription: { id: 'sub_123', status: 'active', period_end: 0, active: true, past_due: false, canceled: false },
      });
      mockGetOverview.mockResolvedValueOnce(noDateResponse);
      wrapper = await mountComponent();
      const billingDateEl = wrapper.find('[data-testid="next-billing-date"]');
      expect(billingDateEl.exists()).toBe(false);
    });

    it('does not display next billing date for free users', async () => {
      mockGetOverview.mockResolvedValueOnce(mockOverviewResponses.free);
      wrapper = await mountComponent({ organizations: [mockFreeOrganization] });
      const billingDateEl = wrapper.find('[data-testid="next-billing-date"]');
      expect(billingDateEl.exists()).toBe(false);
    });
  });
});
