// src/tests/apps/workspace/billing/BillingOverview.spec.ts

import { mount, VueWrapper, flushPromises } from '@vue/test-utils';
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { createPinia, setActivePinia } from 'pinia';
import BillingOverview from '@/apps/workspace/billing/BillingOverview.vue';
import { nextTick, ref } from 'vue';
import {
  createMockOverviewResponse,
  mockOverviewResponses,
} from '@/tests/fixtures/billing.fixture';
import { createTestI18n } from '@tests/setup';

vi.mock('vue-router', () => ({
  useRoute: () => ({
    path: '/billing/on1abc123/overview',
    params: { extid: 'on1abc123' },
    query: {},
  }),
}));
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
const mockCreatePortalSession = vi.fn();
vi.mock('@/services/billing.service', () => ({
  BillingService: {
    getOverview: (...args: unknown[]) => mockGetOverview(...args),
    createPortalSession: (...args: unknown[]) => mockCreatePortalSession(...args),
  },
}));

// Lightweight org shape for store mock (not full Organization type)
const mockOrganization = {
  objid: 'org_123', extid: 'on1abc123', display_name: 'Test Organization',
  description: null, owner_id: 'cust_456', contact_email: 'test@example.com',
  planid: 'identity_plus_v1', entitlements: ['api_access'], limits: { teams: 1 }, is_default: true,
  created: new Date('2024-01-01'), updated: new Date('2024-01-01'),
};
const mockFreeOrganization = {
  objid: 'org_456', extid: 'on2def456', display_name: 'Free Org',
  description: null, owner_id: 'cust_789', contact_email: 'free@example.com',
  planid: '', entitlements: [] as string[], limits: { teams: 0 }, is_default: false,
  created: new Date('2024-01-01'), updated: new Date('2024-01-01'),
};

type MockOrg = typeof mockOrganization;
const storeState = { organizations: [] as MockOrg[] };
const mockFetchOrganizations = vi.fn();
const mockFetchOrganization = vi.fn();

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    get organizations() { return storeState.organizations; },
    fetchOrganizations: mockFetchOrganizations,
    fetchOrganization: mockFetchOrganization,
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
  getPlanLabel: (id: string) => {
    const names: Record<string, string> = {
      identity_plus_v1: 'Identity Plus',
      identity: 'Identity Plus (Early Supporter)',
    };
    return names[id] || id;
  },
  isLegacyPlan: (planId: string) => planId === 'identity',
  isFreePlan: (planId: string) => !planId || planId === 'free' || planId.startsWith('free_'),
}));

// Use shared fixture factory for overview response
const defaultOverviewResponse = createMockOverviewResponse({
  organization: { id: 'org_123', external_id: 'on1abc123', display_name: 'Test Org', billing_email: null },
});

const i18n = createTestI18n();

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
      // Component renders plan info after loading
      expect(wrapper.text()).toContain('web.billing.overview.current_plan');
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
      expect(wrapper.text()).toContain('web.billing.plans.free_plan');
    });
  });

  describe('Entitlements Display', () => {
    it('renders entitlements list from plan features', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('web.billing.features.feature1');
      expect(wrapper.text()).toContain('web.billing.features.feature2');
    });

    it('shows entitlements loading skeleton during load', async () => {
      let resolveOverview: (value: ReturnType<typeof createMockOverviewResponse>) => void;
      storeState.organizations = [mockOrganization];
      mockFetchOrganization.mockResolvedValue(mockOrganization);
      mockGetOverview.mockImplementationOnce(() => new Promise(r => { resolveOverview = r; }));

      wrapper = mount(BillingOverview, {
        global: { plugins: [i18n, pinia], stubs: { RouterLink: routerLinkStub } },
      });

      await nextTick();
      await nextTick();
      expect(wrapper.find('.billing-layout').exists()).toBe(true);

      resolveOverview!(defaultOverviewResponse);
      await flushPromises();
      expect(wrapper.text()).toContain('web.billing.features.feature1');
    });

    it('handles entitlements API error gracefully', async () => {
      mockGetOverview.mockRejectedValueOnce(new Error('Failed to load billing'));
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('Failed to load billing');
      expect(wrapper.find('.billing-layout').exists()).toBe(true);
    });
  });

  describe('URL-based Org Routing', () => {
    it('loads organization data based on URL extid param', async () => {
      const orgs = [mockOrganization, mockFreeOrganization];
      wrapper = await mountComponent({ organizations: orgs });

      // Component loads data for org specified in URL params (on1abc123)
      expect(mockGetOverview).toHaveBeenCalledWith('on1abc123');
      expect(mockFetchOrganization).toHaveBeenCalledWith('on1abc123');
    });

    it('displays organization name from URL param', async () => {
      wrapper = await mountComponent({ organizations: [mockOrganization] });
      // Org selector was removed - routing is now URL-based
      expect(wrapper.find('#org-select').exists()).toBe(false);
    });
  });

  describe('Action Buttons', () => {
    it('shows "Change Plan" button for subscribers', async () => {
      wrapper = await mountComponent();
      expect(wrapper.text()).toContain('web.billing.overview.change_plan');
    });

    it('shows "Upgrade Plan" button for free users', async () => {
      mockGetOverview.mockResolvedValueOnce(mockOverviewResponses.free);
      wrapper = await mountComponent({ organizations: [mockFreeOrganization] });
      expect(wrapper.text()).toContain('web.billing.overview.upgrade_plan');
    });
  });

  describe('Empty State', () => {
    it('shows empty state when no organizations', async () => {
      wrapper = await mountComponent({ organizations: [] });
      expect(wrapper.text()).toContain('web.billing.overview.no_organizations_title');
      expect(wrapper.find('a').exists()).toBe(true);
    });
  });

  describe('Next Billing Date', () => {
    it('displays next billing date when subscription has period_end', async () => {
      wrapper = await mountComponent();
      const billingDateEl = wrapper.find('[data-testid="next-billing-date"]');
      expect(billingDateEl.exists()).toBe(true);
      expect(billingDateEl.text()).toContain('web.billing.overview.next_billing_date');

      const expectedDate = new Date(Number(defaultOverviewResponse.subscription!.period_end) * 1000);
      // Default date_format is 'locale', so output varies by environment.
      // Verify the formatted date contains the expected year.
      expect(billingDateEl.text()).toContain(String(expectedDate.getFullYear()));
    });

    // `period_end` is epoch SECONDS as a decimal string, or null. Each case is
    // a value the wire can carry; none may render a date. '0' has its own case
    // because the truthiness check this replaced excluded 0 by accident, and a
    // parse-then-render would put 1 Jan 1970 on the page.
    it.each([
      ['null, the API value for an org with no recorded period end', null],
      ['an empty string', ''],
      ["'0', an unset field that survived as a zero epoch", '0'],
      ['a non-numeric string', 'not-a-timestamp'],
    ])('does not display next billing date when period_end is %s', async (_label, periodEnd) => {
      const noDateResponse = createMockOverviewResponse({
        organization: { id: 'org_123', external_id: 'on1abc123', display_name: 'Test Org', billing_email: null },
        subscription: {
          id: 'sub_123',
          status: 'active',
          period_end: periodEnd,
          active: true,
          past_due: false,
          canceled: false,
        },
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

  describe('Billing Portal', () => {
    const ownerOrganization = { ...mockOrganization, current_user_role: 'owner' };
    const memberOrganization = { ...mockOrganization, current_user_role: 'member' };
    const portalOverview = createMockOverviewResponse({
      organization: { id: 'org_123', external_id: 'on1abc123', display_name: 'Test Org', billing_email: null },
      portal_available: true,
    });

    let originalLocation: Location;

    beforeEach(() => {
      originalLocation = window.location;
      Object.defineProperty(window, 'location', {
        value: { href: '', origin: 'https://onetimesecret.com' },
        writable: true,
        configurable: true,
      });
    });

    afterEach(() => {
      Object.defineProperty(window, 'location', {
        value: originalLocation,
        writable: true,
        configurable: true,
      });
    });

    it('shows the portal card to an owner when the organization has a billing account', async () => {
      mockGetOverview.mockResolvedValueOnce(portalOverview);
      wrapper = await mountComponent({ organizations: [ownerOrganization] });

      const card = wrapper.find('[data-testid="billing-portal-card"]');
      expect(card.exists()).toBe(true);
      expect(card.text()).toContain('web.billing.portal.open_portal');
    });

    it('hides the portal card from a non-owner member', async () => {
      mockGetOverview.mockResolvedValueOnce(portalOverview);
      wrapper = await mountComponent({ organizations: [memberOrganization] });

      expect(wrapper.find('[data-testid="billing-portal-card"]').exists()).toBe(false);
    });

    it('hides the portal card when the organization has no billing account', async () => {
      mockGetOverview.mockResolvedValueOnce(
        createMockOverviewResponse({ portal_available: false })
      );
      wrapper = await mountComponent({ organizations: [ownerOrganization] });

      expect(wrapper.find('[data-testid="billing-portal-card"]').exists()).toBe(false);
    });

    it('opens the portal session for the organization in the URL', async () => {
      const portalUrl = 'https://billing.stripe.com/p/session/test_123';
      mockGetOverview.mockResolvedValueOnce(portalOverview);
      mockCreatePortalSession.mockResolvedValueOnce({ portal_url: portalUrl });
      wrapper = await mountComponent({ organizations: [ownerOrganization] });

      await wrapper.find('[data-testid="billing-portal-btn"]').trigger('click');
      await flushPromises();

      expect(mockCreatePortalSession).toHaveBeenCalledWith('on1abc123');
      expect(window.location.href).toBe(portalUrl);
    });

    it('does not navigate to a portal_url outside the allowlist', async () => {
      mockGetOverview.mockResolvedValueOnce(portalOverview);
      mockCreatePortalSession.mockResolvedValueOnce({
        portal_url: 'https://evil.example.com/p/session/test_123',
      });
      wrapper = await mountComponent({ organizations: [ownerOrganization] });

      await wrapper.find('[data-testid="billing-portal-btn"]').trigger('click');
      await flushPromises();

      expect(window.location.href).toBe('');
      expect(wrapper.text()).toContain('web.billing.portal.open_error');
    });

    it('shows the API error when the portal session cannot be created', async () => {
      mockGetOverview.mockResolvedValueOnce(portalOverview);
      mockCreatePortalSession.mockRejectedValueOnce(new Error('Failed to open billing portal'));
      wrapper = await mountComponent({ organizations: [ownerOrganization] });

      await wrapper.find('[data-testid="billing-portal-btn"]').trigger('click');
      await flushPromises();

      expect(window.location.href).toBe('');
      expect(wrapper.text()).toContain('Failed to open billing portal');
      expect(
        wrapper.find('[data-testid="billing-portal-btn"]').attributes('disabled')
      ).toBeUndefined();
    });
  });
});
