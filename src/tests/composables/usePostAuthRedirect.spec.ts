// src/tests/composables/usePostAuthRedirect.spec.ts

/**
 * Tests for the billing branch of usePostAuthRedirect.
 *
 * The route-query fallback means `product`/`interval` are user-controlled.
 * These tests pin that both billing destinations are pushed in vue-router's
 * object form ({ path, query }) so reserved characters in those values are
 * encoded by the router instead of being interpreted as URL syntax — a raw
 * `product=x&change=true` must stay ONE query value, not become two.
 */

import { usePostAuthRedirect } from '@/shared/composables/usePostAuthRedirect';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import { createWireOrganization, type OrganizationWire } from '@/tests/fixtures/billing.fixture';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { useRoute, useRouter } from 'vue-router';
import { getRouter } from 'vue-router-mock';
import { setupTestPinia } from '../setup';

// Mock vue-router - must be before any imports that use it
vi.mock('vue-router');

// Mock vue-i18n to provide translation function
vi.mock('vue-i18n', () => ({
  useI18n: () => ({
    t: (key: string) => key,
    locale: { value: 'en' },
  }),
}));

// Mock logging service to suppress debug output during tests
vi.mock('@/services/logging.service', () => ({
  loggingService: {
    debug: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
    info: vi.fn(),
  },
}));

function createMockOrganization(overrides: Partial<OrganizationWire> = {}): OrganizationWire {
  const now = Math.floor(Date.now() / 1000);
  return createWireOrganization({
    objid: 'org_obj_123',
    extid: 'on1234abc',
    owner_id: 'cust_obj_456',
    display_name: 'Test Organization',
    description: null,
    contact_email: 'contact@example.com',
    is_default: true,
    planid: 'free_v1',
    created: now,
    updated: now,
    entitlements: [],
    limits: { teams: 0, total_members_per_org: 0, custom_domains: 0 },
    ...overrides,
  });
}

describe('usePostAuthRedirect - billing destination encoding', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    const bootstrapStore = useBootstrapStore();
    bootstrapStore.authenticated = true;
    bootstrapStore.billing_enabled = true;

    mockRoute = { query: {} };
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as any);
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  it('pushes the checkout destination in object form, reserved characters intact', async () => {
    mockRoute.query = { product: 'x&change=true', interval: 'month#frag' };
    // planid is required-canonical in the org schema, so a validated response
    // can never carry a falsy one; stub the store to reach the checkout branch.
    const orgStore = useOrganizationStore();
    vi.spyOn(orgStore, 'fetchOrganizations').mockResolvedValue([]);
    vi.spyOn(orgStore, 'restorePersistedSelection').mockReturnValue({
      extid: 'on1234abc',
      planid: undefined,
    } as any);

    const { handleBillingRedirect } = usePostAuthRedirect();
    const redirected = await handleBillingRedirect();

    expect(redirected).toBe(true);
    // Object form: the router encodes these values; string interpolation would
    // have let `&change=true` split into a second query parameter.
    expect(router.push).toHaveBeenCalledWith({
      path: '/billing/on1234abc/plans',
      query: { product: 'x&change=true', interval: 'month#frag' },
    });
  });

  it('pushes the plan-change destination in object form, reserved characters intact', async () => {
    mockRoute.query = { product: 'x&change=true', interval: 'year' };
    const org = createMockOrganization({ planid: 'identity_plus_v1' });
    axiosMock.onGet('/api/organizations').reply(200, { records: [org], count: 1 });

    const { handleBillingRedirect } = usePostAuthRedirect();
    const redirected = await handleBillingRedirect();

    expect(redirected).toBe(true);
    expect(router.push).toHaveBeenCalledWith({
      path: `/billing/${org.extid}/plans`,
      query: { product: 'x&change=true', interval: 'year', change: 'true' },
    });
  });
});
