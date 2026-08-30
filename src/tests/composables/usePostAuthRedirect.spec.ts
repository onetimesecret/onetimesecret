// src/tests/composables/usePostAuthRedirect.spec.ts

import { usePostAuthRedirect } from '@/shared/composables/usePostAuthRedirect';
import { loggingService } from '@/services/logging.service';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';
import { useOrganizationStore } from '@/shared/stores/organizationStore';
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
 * Stores are seeded explicitly: app bootstrap is absent in vitest, so
 * billing_enabled defaults to false.
 */
describe('usePostAuthRedirect', () => {
  const seedBillingQuery = () => {
    mockRoute.query = { product: 'identity_plus_v1', interval: 'monthly' };
  };

  const orgOf = (over: { extid?: string; planid?: string } | null) =>
    over as ReturnType<ReturnType<typeof useOrganizationStore>['restorePersistedSelection']>;

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
      vi.mocked(orgStore.restorePersistedSelection).mockReturnValue(orgOf({ extid: 'org_q1' }));

      await usePostAuthRedirect().navigateAfterAuth(undefined);

      expect(orgStore.fetchOrganizations).toHaveBeenCalledTimes(1);
      expect(routerPushMock).toHaveBeenCalledWith({
        path: '/billing/org_q1/plans',
        query: { product: 'identity_plus_v1', interval: 'monthly' },
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
      expect(routerPushMock).not.toHaveBeenCalledWith(
        expect.stringContaining('/billing/plans')
      );
    });

    it('a definitive "no org" (fetch OK, none selected) still abandons the intent', async () => {
      // The retry route exists for TRANSIENT failures; an account with no
      // organization would loop through the guard forever, so the empty
      // result keeps the old fall-through behavior.
      seedBillingQuery();
      useBootstrapStore().billing_enabled = true;
      const orgStore = useOrganizationStore();
      vi.mocked(orgStore.restorePersistedSelection).mockReturnValue(orgOf(null));

      const redirected = await usePostAuthRedirect().handleBillingRedirect(undefined);

      expect(redirected).toBe(false);
      expect(routerPushMock).not.toHaveBeenCalled();
    });
  });
});
