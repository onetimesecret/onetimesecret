// src/tests/apps/workspace/routes/billing.spec.ts

/**
 * Unit tests for billing route guards:
 * - checkBillingEnabled: redirects to dashboard if billing is disabled
 * - createBillingRedirect: redirects to /billing/:extid/:targetPage
 */

import { describe, it, expect, vi, beforeEach } from 'vitest';

// Store state for mocks
let mockBillingEnabled = true;
const mockOrganizations: Array<{ extid: string }> = [];
let mockCurrentOrganization: { extid: string } | null = null;
const mockFetchOrganizations = vi.fn();

vi.mock('@/shared/stores/bootstrapStore', () => ({
  useBootstrapStore: () => ({
    get billing_enabled() { return mockBillingEnabled; },
  }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    get organizations() { return mockOrganizations; },
    get currentOrganization() { return mockCurrentOrganization; },
    fetchOrganizations: mockFetchOrganizations,
  }),
}));

// Import route config after mocks are set up
// We need to re-import the guards by importing the routes module
// Since the guards are not directly exported, we test them via
// the route config's beforeEnter arrays.
import billingRoutes from '@/apps/workspace/routes/billing';

/**
 * Extract guard functions from the route config.
 * The /billing route uses [checkBillingEnabled, createBillingRedirect('overview')]
 */
function getGuardsForPath(path: string) {
  const route = billingRoutes.find(r => r.path === path);
  if (!route?.beforeEnter) return [];
  return Array.isArray(route.beforeEnter)
    ? route.beforeEnter
    : [route.beforeEnter];
}

/** Redirect guard shape: consumes the incoming route, returns the target. */
type BillingRedirectGuard = (to: {
  query: Record<string, string>;
}) => Promise<{ path: string; query: Record<string, string> } | { name: string }>;

/** Minimal stand-in for the `to` route the router passes to beforeEnter. */
const incoming = (query: Record<string, string> = {}) => ({ query });

describe('checkBillingEnabled guard', () => {
  beforeEach(() => {
    mockBillingEnabled = true;
    vi.clearAllMocks();
  });

  it('returns true when billing is enabled', () => {
    mockBillingEnabled = true;
    const guards = getGuardsForPath('/billing');
    const checkBillingEnabled = guards[0] as () => true | { name: string };
    expect(checkBillingEnabled()).toBe(true);
  });

  it('redirects to Dashboard when billing is disabled', () => {
    mockBillingEnabled = false;
    const guards = getGuardsForPath('/billing');
    const checkBillingEnabled = guards[0] as () => true | { name: string };
    expect(checkBillingEnabled()).toEqual({ name: 'Dashboard' });
  });
});

describe('createBillingRedirect guard', () => {
  beforeEach(() => {
    mockBillingEnabled = true;
    mockOrganizations.length = 0;
    mockCurrentOrganization = null;
    mockFetchOrganizations.mockReset();
    vi.clearAllMocks();
  });

  it('redirects to /billing/:extid/overview for /billing route', async () => {
    mockOrganizations.push({ extid: 'org_abc123' });
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(incoming());
    expect(result).toEqual({ path: '/billing/org_abc123/overview', query: {} });
  });

  it('redirects to /billing/:extid/plans for /billing/plans route', async () => {
    mockOrganizations.push({ extid: 'org_abc123' });
    const guards = getGuardsForPath('/billing/plans');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(incoming());
    expect(result).toEqual({ path: '/billing/org_abc123/plans', query: {} });
  });

  // Regression (#4306): returning { path } alone silently drops the incoming
  // query — the post-signup plan intent (/billing/plans?product=&interval=)
  // arrived at the org-scoped plans page with no plan selected.
  it('forwards the plan-intent query params through the rewrite', async () => {
    mockOrganizations.push({ extid: 'org_abc123' });
    const guards = getGuardsForPath('/billing/plans');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(
      incoming({ product: 'identity_plus_v1', interval: 'year', change: 'true' })
    );
    expect(result).toEqual({
      path: '/billing/org_abc123/plans',
      query: { product: 'identity_plus_v1', interval: 'year', change: 'true' },
    });
  });

  it('forwards the query for the /billing overview rewrite too', async () => {
    mockOrganizations.push({ extid: 'org_abc123' });
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(incoming({ product: 'identity_plus_v1' }));
    expect(result).toEqual({
      path: '/billing/org_abc123/overview',
      query: { product: 'identity_plus_v1' },
    });
  });

  it('preserves plan-selection query params when resolving the current organization', async () => {
    mockOrganizations.push({ extid: 'org_abc123' });
    const guards = getGuardsForPath('/billing/plans');
    const redirect = guards[1] as unknown as (to: { query: object }) => Promise<{
      path: string;
      query: object;
    }>;
    const result = await redirect({
      query: { product: 'identity_plus_v1', interval: 'monthly' },
    });

    expect(result).toEqual({
      path: '/billing/org_abc123/plans',
      query: { product: 'identity_plus_v1', interval: 'monthly' },
    });
  });

  it('fetches organizations when store is empty', async () => {
    mockFetchOrganizations.mockImplementation(() => {
      mockOrganizations.push({ extid: 'org_fetched' });
    });
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    await redirect(incoming());
    expect(mockFetchOrganizations).toHaveBeenCalled();
  });

  it('does not fetch when organizations already loaded', async () => {
    mockOrganizations.push({ extid: 'org_existing' });
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    await redirect(incoming());
    expect(mockFetchOrganizations).not.toHaveBeenCalled();
  });

  it('prefers currentOrganization over first in list', async () => {
    mockOrganizations.push(
      { extid: 'org_first' },
      { extid: 'org_second' },
    );
    mockCurrentOrganization = { extid: 'org_second' };
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(incoming());
    expect(result).toEqual({ path: '/billing/org_second/overview', query: {} });
  });

  it('falls back to first org when no currentOrganization', async () => {
    mockOrganizations.push(
      { extid: 'org_first' },
      { extid: 'org_second' },
    );
    mockCurrentOrganization = null;
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(incoming());
    expect(result).toEqual({ path: '/billing/org_first/overview', query: {} });
  });

  it('redirects to Dashboard when no organizations exist', async () => {
    mockFetchOrganizations.mockResolvedValue(undefined);
    const guards = getGuardsForPath('/billing');
    const redirect = guards[1] as BillingRedirectGuard;
    const result = await redirect(incoming());
    expect(result).toEqual({ name: 'Dashboard' });
  });
});
