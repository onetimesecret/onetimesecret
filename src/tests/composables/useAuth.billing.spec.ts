// src/tests/composables/useAuth.billing.spec.ts

/**
 * Tests for billing redirect safety checks in useAuth composable.
 *
 * These tests verify that handleBillingRedirect() correctly:
 * 1. Checks billing_redirect.valid flag before redirecting
 * 2. Checks subscription status before redirecting to checkout
 * 3. Routes to appropriate destinations based on current subscription state
 */

import { loggingService } from '@/services/logging.service';
import { useAuth } from '@/shared/composables/useAuth';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import {
  authenticatedBootstrap,
  mfaPendingBootstrap,
  newerSnapshot,
} from '@/tests/fixtures/bootstrap.fixture';
import { toWire } from '@/tests/fixtures/bootstrap-wire';
import { createWireOrganization, type OrganizationWire } from '@/tests/fixtures/billing.fixture';
import type AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
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
    info: vi.fn(),
    warn: vi.fn(),
    error: vi.fn(),
  },
}));

/**
 * Creates mock Organization API response for auth billing tests.
 *
 * Wraps canonical createWireOrganization with auth-specific defaults:
 * - is_default: true (most tests need a default org)
 * - planid: 'free_v1' (tests verify redirect behavior for users without paid
 *   plans; the value must match the planid regex or the store rejects the
 *   whole response and the billing flow is never reached)
 *
 * Returns wire format (epoch timestamps) for API response mocking.
 */
// The auth store's init() runs when the store is created (the real auto-init
// plugin) and, seeing a session that has no ordering watermark yet, refreshes
// once. The login under test then refreshes again. A real server answers each
// request with a newer snapshot_version; a frozen mock would make the second
// answer the `not-newer` anomaly and force a page load. Advance it per reply.
let snapshotVersionBump = 0;

function nextSnapshot(payload: Parameters<typeof newerSnapshot>[0]) {
  return newerSnapshot(payload, ++snapshotVersionBump);
}

/**
 * Pin the auto-init refresh before driving login.
 *
 * useAuth() creates the auth store, whose init() dispatches the unordered-
 * hydration GET /bootstrap/me synchronously. login() then POSTs and refreshes
 * again. Against the zero-delay axios mock both settle on microtask FIFO, so
 * the auto-init snapshot is always applied first and the login refresh is the
 * newer one. That ordering is what keeps the login refresh from being reported
 * as `superseded` (login() returns false, error stays null). Waiting for the
 * watermark makes the order explicit instead of relying on scheduler FIFO, so
 * a future false from login() is a product change, not a race in this file.
 */
async function authReady() {
  await vi.waitFor(() => expect(useBootstrapStore().watermark).not.toBeNull());
}

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

/**
 * Helper to set up bootstrapStore with authentication and billing configuration
 */
function setupBootstrapStoreState(
  store: ReturnType<typeof useBootstrapStore>,
  config: {
    authenticated?: boolean;
    billing_enabled?: boolean;
    shrimp?: string;
  } = {}
) {
  store.authenticated = config.authenticated ?? true;
  store.billing_enabled = config.billing_enabled ?? true;
  store.shrimp = config.shrimp ?? 'test-shrimp-token';
}

describe('useAuth - Billing Redirect Safety Checks', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    // Get bootstrap store and set up state
    bootstrapStore = useBootstrapStore();
    setupBootstrapStoreState(bootstrapStore, {
      authenticated: true,
      billing_enabled: true,
      shrimp: 'test-shrimp-token',
    });

    // Set up mock route with query params
    mockRoute = { query: {} };

    // Wire up vue-router mocks
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as any);

    // Mock the /bootstrap/me endpoint used by authStore.setAuthenticated.
    // ADR-046#auth-completion-caller-contract: post-#4464 the coordinator refuses a snapshot
    // without cust (effectiveAuthStatus → 'unavailable'). Use the canonical authenticated
    // fixture (wire encoding) so ensureAuthenticated / ensureMfaPending land
    // as 'applied'.
    axiosMock.onGet('/bootstrap/me').reply(() => [
      200,
      {
        ...toWire(nextSnapshot(authenticatedBootstrap)),
        billing_enabled: true,
        shrimp: 'new-shrimp-token',
      },
    ]);
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  // Helper to set route query params
  function setRouteQuery(query: Record<string, string>) {
    mockRoute.query = query;
  }

  describe('handleBillingRedirect - Missing Billing Params', () => {
    it('should not redirect when product param is missing', async () => {
      // Set route without product param
      setRouteQuery({ interval: 'month' });

      const { login } = useAuth();
      await authReady();

      // Mock successful login response
      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      // Mock organizations fetch
      axiosMock.onGet('/api/organizations').reply(200, {
        records: [createMockOrganization()],
        count: 1,
      });

      await login('test@example.com', 'password123');

      // Should redirect to dashboard, not billing
      expect(router.push).toHaveBeenCalledWith('/');
    });

    it('should not redirect when interval param is missing', async () => {
      // Set route without interval param
      setRouteQuery({ product: 'identity' });

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      axiosMock.onGet('/api/organizations').reply(200, {
        records: [createMockOrganization()],
        count: 1,
      });

      await login('test@example.com', 'password123');

      // Should redirect to dashboard, not billing
      expect(router.push).toHaveBeenCalledWith('/');
    });

    it('should not redirect when both billing params are missing', async () => {
      // No billing params in route
      setRouteQuery({});

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      await login('test@example.com', 'password123');

      // Should redirect to dashboard
      expect(router.push).toHaveBeenCalledWith('/');
    });
  });

  describe('handleBillingRedirect - Billing Disabled', () => {
    /**
     * login() ends in authStore.setAuthenticated(true), which refetches
     * /bootstrap/me and overwrites the store from that body. Seeding the store
     * alone is therefore NOT enough to disable billing — the beforeEach mock
     * (billing_enabled: true) wins, and these tests would assert nothing.
     * Re-mock the endpoint so the disabled state survives the refetch.
     */
    const disableBillingOnRefetch = (value: boolean | undefined) => {
      // ADR-046#auth-completion-caller-contract: carry the canonical authenticated identity so the
      // refresh coordinator accepts the snapshot. Strip billing_enabled from
      // the fixture so the caller's value (or its absence) is what the store
      // reads back.
      axiosMock.onGet('/bootstrap/me').reply(() => {
        const { billing_enabled: _drop, ...rest } = toWire(nextSnapshot(authenticatedBootstrap));
        void _drop;
        return [
          200,
          {
            ...rest,
            ...(value === undefined ? {} : { billing_enabled: value }),
            shrimp: 'new-shrimp-token',
          },
        ];
      });
    };

    it('should not redirect when billing is disabled globally', async () => {
      // Set billing_enabled to false via bootstrapStore
      bootstrapStore.billing_enabled = false;
      disableBillingOnRefetch(false);

      setRouteQuery({ product: 'identity', interval: 'month' });

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      await login('test@example.com', 'password123');

      // Should redirect to dashboard, not billing
      expect(router.push).toHaveBeenCalledWith('/');
    });

    it('should not redirect when billing_enabled is undefined', async () => {
      // Set billing_enabled to undefined via bootstrapStore. $patch (not direct
      // assignment) because the state type's billing_enabled is a non-optional
      // boolean (schema default(false)) — $patch's _DeepPartial widens it to
      // accept undefined for this "field absent from response" scenario.
      bootstrapStore.$patch({ billing_enabled: undefined });
      disableBillingOnRefetch(undefined);

      setRouteQuery({ product: 'identity', interval: 'month' });

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      await login('test@example.com', 'password123');

      // Should redirect to dashboard
      expect(router.push).toHaveBeenCalledWith('/');
    });
  });

  describe('handleBillingRedirect - No Organization Found', () => {
    it('should redirect to dashboard when no organization exists', async () => {
      setRouteQuery({ product: 'identity', interval: 'month' });

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      // No organizations
      axiosMock.onGet('/api/organizations').reply(200, {
        records: [],
        count: 0,
      });

      await login('test@example.com', 'password123');

      // Should fall back to dashboard
      expect(router.push).toHaveBeenCalledWith('/');
    });

    it('should keep the plan intent when the organizations fetch fails', async () => {
      // #4306: a TRANSIENT org-resolution failure no longer discards the
      // selection. The extid-less plans route's guard retries resolution and
      // forwards the query, so the user still reaches checkout.
      setRouteQuery({ product: 'identity', interval: 'month' });

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      // Organizations fetch fails
      axiosMock.onGet('/api/organizations').reply(500, {
        error: 'Internal server error',
      });

      await login('test@example.com', 'password123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/billing/plans',
        query: { product: 'identity', interval: 'month' },
      });
    });
  });

  describe('handleBillingRedirect - MFA Flow', () => {
    // When MFA is required the user goes to /mfa-verify instead of billing —
    // the billing redirect only happens after the second factor succeeds
    // (MfaChallenge → navigateAfterAuth). #4306: the plan-intent query pair is
    // forwarded so the completion path keeps its fallback tier.

    beforeEach(() => {
      // ADR-046#auth-completion-caller-contract: ensureMfaPending only navigates when the follow-up
      // snapshot lands as `mfa_pending`. The outer beforeEach mocks the
      // authenticated fixture; override it here so the MFA flow's refresh
      // sees an mfa_pending payload.
      axiosMock
        .onGet('/bootstrap/me')
        .reply(() => [200, toWire(nextSnapshot(mfaPendingBootstrap))]);
    });

    it('should not attempt billing redirect when MFA is required', async () => {
      setRouteQuery({ product: 'identity', interval: 'month' });
      const { login } = useAuth();
      await authReady();
      axiosMock.onPost('/auth/login').reply(200, {
        success: 'MFA verification required',
        mfa_required: true,
        mfa_auth_url: '/auth/otp-auth',
        mfa_methods: ['totp'],
      });

      await login('test@example.com', 'password123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/mfa-verify',
        query: { product: 'identity', interval: 'month' },
      });
      expect(axiosMock.history.get.filter((r) => r.url === '/api/organizations')).toHaveLength(0);
    });

    it('forwards ?redirect alongside the plan intent to /mfa-verify', async () => {
      setRouteQuery({ product: 'identity', interval: 'month', redirect: '/dashboard' });
      const { login } = useAuth();
      await authReady();
      axiosMock.onPost('/auth/login').reply(200, {
        success: 'MFA verification required',
        mfa_required: true,
      });

      await login('test@example.com', 'password123');

      expect(router.push).toHaveBeenCalledWith({
        path: '/mfa-verify',
        query: { product: 'identity', interval: 'month', redirect: '/dashboard' },
      });
    });

    it('pushes a bare /mfa-verify when there is nothing to forward', async () => {
      const { login } = useAuth();
      await authReady();
      axiosMock.onPost('/auth/login').reply(200, {
        success: 'MFA verification required',
        mfa_required: true,
      });

      await login('test@example.com', 'password123');

      expect(router.push).toHaveBeenCalledWith({ path: '/mfa-verify', query: undefined });
    });
  });

  describe('handleBillingRedirect - Error Handling', () => {
    it('should gracefully handle router push errors', async () => {
      setRouteQuery({ product: 'identity', interval: 'month' });

      // Mock router.push to throw on the org-scoped billing route only. The
      // #4306 fallback pushes the extid-less /billing/plans route, which must
      // succeed here or the failure has nowhere graceful to land.
      // NOTE: this implementation LEAKS — afterEach's clearAllMocks() clears
      // recorded calls, not implementations — so any later test that expects
      // a billing push must reinstate a passthrough first (see below).
      (router.push as Mock).mockImplementation(async (path: string | object) => {
        const pathStr = typeof path === 'string' ? path : (path as { path?: string }).path || '';
        if (pathStr.startsWith('/billing/on1234abc/')) {
          throw new Error('Navigation aborted');
        }
        return Promise.resolve();
      });

      const { login, error } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      axiosMock.onGet('/api/organizations').reply(200, {
        records: [createMockOrganization()],
        count: 1,
      });

      // Should not throw, should handle gracefully
      const result = await login('test@example.com', 'password123');

      // Login should still succeed despite navigation error, and the plan
      // intent survives on the extid-less route whose guard retries the org.
      // A thrown verification_unavailable lands in `error` via onError; a
      // `superseded` return leaves it null. Checking it first names the branch.
      expect(error.value).toBeNull();
      expect(result).toBe(true);
      expect(router.push).toHaveBeenCalledWith(
        expect.objectContaining({ path: '/billing/on1234abc/plans' })
      );
      expect(router.push).toHaveBeenCalledWith({
        path: '/billing/plans',
        query: { product: 'identity', interval: 'month' },
      });
    });

    it('should handle network errors during organization fetch gracefully', async () => {
      // Undo the throwing implementation the previous test installed on the
      // shared router spy; this test asserts on the push that FOLLOWS the
      // failure, so navigation itself must succeed here.
      (router.push as Mock).mockImplementation(async () => Promise.resolve());
      setRouteQuery({ product: 'identity', interval: 'month' });

      const { login } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, {
        success: 'Logged in successfully',
      });

      // Network error on organizations fetch
      axiosMock.onGet('/api/organizations').networkError();

      // Should not throw
      const result = await login('test@example.com', 'password123');

      // Login succeeds and the intent survives the failure (#4306) — the
      // extid-less plans route's guard retries org resolution.
      expect(result).toBe(true);
      expect(router.push).toHaveBeenCalledWith({
        path: '/billing/plans',
        query: { product: 'identity', interval: 'month' },
      });
    });
  });

  describe('handleBillingRedirect - Login Flow Integration', () => {
    it('should preserve billing params through successful login', async () => {
      setRouteQuery({ product: 'professional', interval: 'year' });

      const { login } = useAuth();
      await authReady();

      // Verify billing params are sent to login endpoint
      let loginPayload: Record<string, unknown> | undefined;
      axiosMock.onPost('/auth/login').reply((config) => {
        loginPayload = JSON.parse(config.data);
        return [200, { success: 'Logged in successfully' }];
      });

      axiosMock.onGet('/api/organizations').reply(200, {
        records: [createMockOrganization()],
        count: 1,
      });

      await login('test@example.com', 'password123');

      // Billing params should have been included in login request
      expect(loginPayload).toMatchObject({
        product: 'professional',
        interval: 'year',
      });
    });

    it('routes to the org-scoped plan change flow after login from the route query fallback', async () => {
      // No billing_redirect in the login response, so the plan intent comes
      // from the route query. createMockOrganization() is free_v1, which is a
      // plan like any other: the redirect carries `change: 'true'`.
      setRouteQuery({ product: 'identity', interval: 'month' });

      const { login, isLoading } = useAuth();
      await authReady();

      axiosMock.onPost('/auth/login').reply(200, { success: 'Logged in successfully' });
      const org = createMockOrganization();
      axiosMock.onGet('/api/organizations').reply(200, { records: [org], count: 1 });

      expect(isLoading.value).toBe(false);
      expect(await login('test@example.com', 'password123')).toBe(true);
      expect(isLoading.value).toBe(false);

      expect(router.push).toHaveBeenCalledWith({
        path: `/billing/${org.extid}/plans`,
        query: { product: 'identity', interval: 'month', change: 'true' },
      });
    });
  });
});

/**
 * Tests for future billing_redirect.valid flag implementation
 *
 * These tests are placeholders for when the valid flag is implemented
 * in the backend response and handleBillingRedirect checks it.
 */
describe('useAuth - Billing Redirect Valid Flag (Future)', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  function setRouteQuery(query: Record<string, string>) {
    mockRoute.query = query;
  }

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    // Get bootstrap store and set up state
    bootstrapStore = useBootstrapStore();
    setupBootstrapStoreState(bootstrapStore, {
      authenticated: true,
      billing_enabled: true,
      shrimp: 'test-shrimp-token',
    });

    mockRoute = { query: {} };
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as any);

    // Mock the /bootstrap/me endpoint. ADR-046#auth-completion-caller-contract: canonical
    // authenticated fixture so the refresh coordinator lands the snapshot with cust.
    axiosMock.onGet('/bootstrap/me').reply(() => [
      200,
      {
        ...toWire(nextSnapshot(authenticatedBootstrap)),
        billing_enabled: true,
        shrimp: 'new-shrimp-token',
      },
    ]);
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  it('should NOT redirect when billing_redirect.valid is false', async () => {
    // The backend resolved the plan and rejected it. The verdict wins over the
    // query pair, so login goes to the dashboard, not checkout. The payload
    // has the shape build_billing_redirect_info sends (apps/web/auth/config/
    // hooks/billing.rb), so it parses as the invalid member rather than being
    // stripped.
    setRouteQuery({ product: 'invalid_product', interval: 'month' });

    const { login } = useAuth();
    await authReady();

    axiosMock.onPost('/auth/login').reply(200, {
      success: 'Logged in successfully',
      billing_redirect: {
        product: 'invalid_product',
        interval: 'month',
        valid: false,
        error: 'Invalid product identifier',
      },
    });

    axiosMock.onGet('/api/organizations').reply(200, {
      records: [createMockOrganization()],
      count: 1,
    });

    await login('test@example.com', 'password123');

    // Should redirect to dashboard when plan is invalid
    expect(router.push).toHaveBeenCalledWith('/');
  });

  it('parses a partial billing_redirect at login and skips checkout', async () => {
    // Login from /signin?product=x (no interval): the server answers with the
    // missing half as null. The body must parse as the invalid verdict (the
    // warn proves it was not stripped) and yield no checkout.
    setRouteQuery({ product: 'identity_plus_v1' });

    const { login } = useAuth();
    await authReady();

    axiosMock.onPost('/auth/login').reply(200, {
      success: 'Logged in successfully',
      billing_redirect: {
        product: 'identity_plus_v1',
        interval: null,
        valid: false,
        error: 'Missing product or interval',
      },
    });

    expect(await login('test@example.com', 'password123')).toBe(true);

    expect(loggingService.warn).toHaveBeenCalledWith(
      '[postAuthRedirect] Billing redirect skipped - backend marked plan as invalid',
      { product: 'identity_plus_v1', interval: null, error: 'Missing product or interval' }
    );
    expect(axiosMock.history.get.some((req) => req.url === '/api/organizations')).toBe(false);
    expect(router.push).toHaveBeenCalledWith('/');
  });

  it('routes a valid billing_redirect for a free_v1 org to the org-scoped plan change flow', async () => {
    // planid is required by organizationSchema (default 'free_v1'), so a free
    // org is routed relative to its current plan like any other. The plans
    // page ignores `change` and picks checkout vs plan-change from the backend
    // subscription status, so this is also the checkout path for free orgs.
    setRouteQuery({ product: 'identity', interval: 'month' });

    const { login } = useAuth();
    await authReady();

    axiosMock.onPost('/auth/login').reply(200, {
      success: 'Logged in successfully',
      billing_redirect: {
        valid: true,
        product: 'identity',
        interval: 'month',
      },
    });

    const org = createMockOrganization(); // free_v1
    axiosMock.onGet('/api/organizations').reply(200, {
      records: [org],
      count: 1,
    });

    expect(await login('test@example.com', 'password123')).toBe(true);

    expect(loggingService.debug).toHaveBeenCalledWith(
      '[postAuthRedirect] Using validated billing redirect from response',
      { product: 'identity', interval: 'month' }
    );
    expect(router.push).toHaveBeenCalledWith({
      path: `/billing/${org.extid}/plans`,
      query: { product: 'identity', interval: 'month', change: 'true' },
    });
  });
});

/**
 * Tests for subscription status checking
 *
 * These tests verify handleBillingRedirect behavior when users have
 * existing subscriptions and request billing redirects.
 */
describe('useAuth - Subscription Status Checks', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  function setRouteQuery(query: Record<string, string>) {
    mockRoute.query = query;
  }

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    // Get bootstrap store and set up state
    bootstrapStore = useBootstrapStore();
    setupBootstrapStoreState(bootstrapStore, {
      authenticated: true,
      billing_enabled: true,
      shrimp: 'test-shrimp-token',
    });

    mockRoute = { query: {} };
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as any);

    // Mock the /bootstrap/me endpoint. ADR-046#auth-completion-caller-contract: canonical
    // authenticated fixture so the refresh coordinator lands the snapshot with cust.
    axiosMock.onGet('/bootstrap/me').reply(() => [
      200,
      {
        ...toWire(nextSnapshot(authenticatedBootstrap)),
        billing_enabled: true,
        shrimp: 'new-shrimp-token',
      },
    ]);
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  it('should redirect to billing overview when already subscribed to SAME plan', async () => {
    setRouteQuery({ product: 'identity', interval: 'month' });

    const { login } = useAuth();
    await authReady();

    axiosMock.onPost('/auth/login').reply(200, {
      success: 'Logged in successfully',
    });

    // Organization already has identity plan
    const org = createMockOrganization({
      planid: 'identity',
    });
    axiosMock.onGet('/api/organizations').reply(200, {
      records: [org],
      count: 1,
    });

    await login('test@example.com', 'password123');

    // Should redirect to billing overview, not checkout
    // since they already have this plan
    expect(router.push).toHaveBeenCalledWith(`/billing/${org.extid}/overview`);
  });

  it('should redirect to plan change flow when subscribed to DIFFERENT plan', async () => {
    setRouteQuery({ product: 'unlimited', interval: 'month' });

    const { login } = useAuth();
    await authReady();

    axiosMock.onPost('/auth/login').reply(200, {
      success: 'Logged in successfully',
    });

    // Organization has identity plan but trying to get unlimited
    const org = createMockOrganization({
      planid: 'identity',
    });
    axiosMock.onGet('/api/organizations').reply(200, {
      records: [org],
      count: 1,
    });

    await login('test@example.com', 'password123');

    // Should redirect to plan change flow
    expect(router.push).toHaveBeenCalledWith({
      path: `/billing/${org.extid}/plans`,
      query: { product: 'unlimited', interval: 'month', change: 'true' },
    });
  });

  it('should redirect to plan change flow when on free plan upgrading to paid', async () => {
    setRouteQuery({ product: 'identity', interval: 'month' });

    const { login } = useAuth();
    await authReady();

    axiosMock.onPost('/auth/login').reply(200, {
      success: 'Logged in successfully',
    });

    // Organization on free plan
    const org = createMockOrganization({
      planid: 'free_v1',
    });
    axiosMock.onGet('/api/organizations').reply(200, {
      records: [org],
      count: 1,
    });

    await login('test@example.com', 'password123');

    // Should redirect to plans with change=true (free is treated as existing plan)
    expect(router.push).toHaveBeenCalledWith({
      path: `/billing/${org.extid}/plans`,
      query: { product: 'identity', interval: 'month', change: 'true' },
    });
  });
});

/**
 * Tests for signup flow billing params preservation
 */
describe('useAuth - Signup Flow Billing Params', () => {
  let axiosMock: AxiosMockAdapter;
  let router: ReturnType<typeof getRouter>;
  let mockRoute: { query: Record<string, string> };
  let bootstrapStore: ReturnType<typeof useBootstrapStore>;

  // Helper to set route query params
  function setRouteQuery(query: Record<string, string>) {
    mockRoute.query = query;
  }

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock!;
    router = getRouter();

    // Get bootstrap store and set up state
    bootstrapStore = useBootstrapStore();
    setupBootstrapStoreState(bootstrapStore, {
      authenticated: false,
      billing_enabled: true,
      shrimp: 'test-shrimp-token',
    });

    // Set up mock route with query params
    mockRoute = { query: {} };

    // Wire up vue-router mocks
    vi.mocked(useRouter).mockReturnValue(router);
    vi.mocked(useRoute).mockReturnValue(mockRoute as any);
  });

  afterEach(() => {
    axiosMock.restore();
    vi.clearAllMocks();
    router.reset();
  });

  it('should preserve billing params when redirecting to check-email after signup', async () => {
    setRouteQuery({ product: 'identity', interval: 'month' });

    const { signup } = useAuth();

    // Capture what params were sent to create-account
    let signupPayload: Record<string, unknown> | undefined;
    axiosMock.onPost('/auth/create-account').reply((config) => {
      signupPayload = JSON.parse(config.data);
      return [200, { success: 'Account created successfully', next_action: 'verify_email' }];
    });

    await signup('test@example.com', 'password123');

    // Billing params should have been sent with signup
    expect(signupPayload).toMatchObject({
      product: 'identity',
      interval: 'month',
    });

    // Should redirect to the "check your email" page with billing params
    // preserved in the query, and the email handed over via router history
    // state (PII must not ride in the URL — see src/utils/pii.ts).
    expect(router.push).toHaveBeenCalledWith({
      path: '/check-email',
      query: { product: 'identity', interval: 'month' },
      state: { checkEmailAddress: 'test@example.com' },
    });
  });

  it('should redirect to check-email with only the email when no billing params present', async () => {
    setRouteQuery({});

    const { signup } = useAuth();

    axiosMock.onPost('/auth/create-account').reply(200, {
      success: 'Account created successfully',
      next_action: 'verify_email',
    });

    await signup('test@example.com', 'password123');

    // With no billing params, the redirect carries no query at all — just the
    // email, handed over via router history state (never the URL).
    expect(router.push).toHaveBeenCalledWith({
      path: '/check-email',
      state: { checkEmailAddress: 'test@example.com' },
    });
  });
});
