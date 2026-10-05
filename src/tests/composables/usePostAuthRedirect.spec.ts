// src/tests/composables/usePostAuthRedirect.spec.ts

import { loginResponseSchema } from '@/schemas/api/auth/responses/auth';
import { loggingService } from '@/services/logging.service';
import { usePostAuthRedirect } from '@/shared/composables/usePostAuthRedirect';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
import type { Organization } from '@/types/organization';
import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// The composable only needs t(); pass-through keeps assertions on i18n keys.
vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: (key: string) => key }),
}));

// Factories dereference lazily, so mutating these consts per-test works.
const mockRoute = { path: '/signin', query: {} as Record<string, unknown> };
const routerPushMock = vi.fn();
vi.mock('vue-router', () => ({
  useRoute: () => mockRoute,
  useRouter: () => ({ push: routerPushMock, replace: vi.fn() }),
}));

vi.mock('@/services/logging.service', () => ({
  loggingService: { debug: vi.fn(), info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

/**
 * usePostAuthRedirect — precedence and failure-path behavior (#4305/#4306).
 *
 * Focus: the org-resolution FAILURE path must not drop a valid billing
 * intent. The extid-less /billing/plans route's guard (createBillingRedirect)
 * retries org resolution and preserves the query, so on a transient fetch
 * failure we hand the intent to that route — via `{ path, query }`, which
 * encodes each value (product/interval can originate from the route query,
 * so a raw interpolated URL would be injectable).
 *
 * Every billing destination is pinned in that object form for the same
 * reason: a raw `product=x&change=true` must stay ONE query value.
 *
 * Stores are seeded explicitly: app bootstrap is absent in vitest, so
 * billing_enabled defaults to false.
 */
describe('usePostAuthRedirect', () => {
  const seedBillingQuery = () => {
    mockRoute.query = { product: 'identity_plus_v1', interval: 'monthly' };
  };

  // fetchOrganizations is stubbed, so seed the list it would have loaded. The
  // composable resolves the org from that list (current, else default/first).
  const seedOrgs = (
    orgStore: ReturnType<typeof useOrganizationStore>,
    ...orgs: { objid?: string; extid?: string; planid?: string; is_default?: boolean }[]
  ) => {
    orgStore.organizations = orgs as Organization[];
  };

  beforeEach(() => {
    vi.clearAllMocks();
    setActivePinia(createTestingPinia({ createSpy: vi.fn }));
    mockRoute.query = {};
  });

  describe('billing intent via the query tier (WebAuthn — no response body)', () => {
    it('routes to the org plans page from query params alone', async () => {
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, { extid: 'org_q1' });

      await usePostAuthRedirect().navigateAfterAuth(undefined);

      expect(orgStore.fetchOrganizations).toHaveBeenCalledTimes(1);
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_q1/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
      });
    });

    it('keeps reserved characters in ONE query param on the checkout destination', async () => {
      mockRoute.query = { product: 'x&change=true', interval: 'month#frag' };
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, { extid: 'org_q1' });

      await usePostAuthRedirect().handleBillingRedirect(undefined);

      // String interpolation would have split `&change=true` into a second param.
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_q1/plans',
        query: { product: 'x&change=true', interval: 'month#frag' },
      });
    });

    it('requires BOTH product and interval — a lone product falls through to /', async () => {
      mockRoute.query = { product: 'identity_plus_v1' };
      useBootstrapStore().billing_enabled = true;

      await usePostAuthRedirect().navigateAfterAuth(undefined);

      expect(useOrganizationStore().fetchOrganizations).not.toHaveBeenCalled();
      expect(routerPushMock).toHaveBeenCalledWith('/');
    });
  });

  describe('invalid server verdict', () => {
    it('blocks checkout for a partial verdict even with a full query pair', async () => {
      // The server's verdict outranks the query tier: an invalid one must not
      // fall back to the route's product/interval.
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const response = loginResponseSchema.parse({
        success: 'ok',
        billing_redirect: {
          product: null,
          interval: 'monthly',
          valid: false,
          error: 'Missing product or interval',
        },
      });

      const redirected = await usePostAuthRedirect().handleBillingRedirect(response);

      expect(redirected).toBe(false);
      expect(useOrganizationStore().fetchOrganizations).not.toHaveBeenCalled();
      expect(loggingService.warn).toHaveBeenCalledWith(
        '[postAuthRedirect] Billing redirect skipped - backend marked plan as invalid',
        { product: null, interval: 'monthly', error: 'Missing product or interval' }
      );
    });
  });

  describe('existing subscription (plan-change destination)', () => {
    it('pushes the change flow in object form, reserved characters intact', async () => {
      mockRoute.query = { product: 'x&change=true', interval: 'year' };
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, { extid: 'org_sub1', planid: 'identity_plus_v1' });

      const redirected = await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(redirected).toBe(true);
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_sub1/plans',
        query: { product: 'x&change=true', interval: 'year', change: 'true' },
      });
    });

    it('sends an already-subscribed user to the billing overview', async () => {
      mockRoute.query = { product: 'identity_plus_v1', interval: 'year' };
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, { extid: 'org_sub1', planid: 'identity_plus_v1' });

      const redirected = await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(redirected).toBe(true);
      expect(routerPushMock).toHaveBeenCalledWith('/billing/org_sub1/overview');
    });
  });

  describe('org resolution failure with a valid billing intent', () => {
    it('pushes the extid-less plans route with the query intact (guard retries)', async () => {
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.fetchOrganizations).mockRejectedValue(new Error('network down'));

      const redirected = await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(redirected).toBe(true);
      expect(loggingService.error).toHaveBeenCalledTimes(1);
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
      });
    });

    it('keeps a query-tier value with & or # in ONE query param (no injection)', async () => {
      // product/interval reach here straight off the route query when the
      // response carries no billing_redirect (the WebAuthn/fallback tier).
      // String interpolation would have split this into extra params.
      mockRoute.query = {
        product: 'identity_plus_v1&admin=1',
        interval: 'monthly#frag',
      };
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.fetchOrganizations).mockRejectedValue(new Error('network down'));

      await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/plans',
        query: { product: 'identity_plus_v1&admin=1', interval: 'monthly#frag' },
      });
    });

    it('uses the response-supplied intent when present', async () => {
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.fetchOrganizations).mockRejectedValue(new Error('500'));

      await usePostAuthRedirect().navigateAfterAuth({
        success: 'ok',
        billing_redirect: { product: 'identity_plus_v1', interval: 'year', valid: true },
      });

      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/plans',
        query: { product: 'identity_plus_v1', interval: 'year' },
      });
      // The intent won: no fall-through to '/' after the billing push.
      expect(routerPushMock).toHaveBeenCalledTimes(1);
    });

    it('does NOT take the billing path when the failure happens without billing params', async () => {
      mockRoute.query = { redirect: '/dashboard' };
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.fetchOrganizations).mockRejectedValue(new Error('network down'));

      await usePostAuthRedirect().navigateAfterAuth(undefined);

      // No intent ⇒ org fetch is never attempted; existing fallback applies.
      expect(orgStore.fetchOrganizations).not.toHaveBeenCalled();
      expect(routerPushMock).toHaveBeenCalledWith('/dashboard');
      expect(routerPushMock).toHaveBeenCalledTimes(1);
    });

    it('billing disabled ⇒ never the billing path, even with valid params and a broken org fetch', async () => {
      seedBillingQuery();
      // billing_enabled stays at its default (false) — self-hosted installs.
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.fetchOrganizations).mockRejectedValue(new Error('network down'));

      await usePostAuthRedirect().navigateAfterAuth(undefined);

      expect(orgStore.fetchOrganizations).not.toHaveBeenCalled();
      expect(routerPushMock).toHaveBeenCalledWith('/');
      expect(routerPushMock).not.toHaveBeenCalledWith(expect.stringContaining('/billing/plans'));
    });

    it('a definitive "no org" (fetch OK, none selected) still abandons the intent', async () => {
      // The retry route exists for TRANSIENT failures; an account with no
      // organization would loop through the guard forever, so the empty
      // result keeps the old fall-through behavior.
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore);

      const redirected = await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(redirected).toBe(false);
      expect(routerPushMock).not.toHaveBeenCalled();
    });
  });

  describe('which organization the billing redirect targets (#4565)', () => {
    const personal = { objid: 'o_default', extid: 'org_default', is_default: true };
    const team = { objid: 'o_team', extid: 'org_team' };

    it('uses the list record of the current (server-seeded) organization', async () => {
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, personal, team);
      // The bootstrap seed is a minimal record; the list record is the one
      // that carries the plan, so the lookup goes by objid into the list.
      orgStore.currentOrganization = { objid: 'o_team', extid: 'org_team' } as Organization;

      await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_team/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
      });
    });

    it('falls back to the default organization when none is current', async () => {
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, team, personal);

      await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_default/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
      });
    });

    it('falls back to the default organization when the current one is not in the list', async () => {
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      seedOrgs(orgStore, team, personal);
      orgStore.currentOrganization = { objid: 'o_gone', extid: 'org_gone' } as Organization;

      await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_default/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
      });
    });
  });
});
