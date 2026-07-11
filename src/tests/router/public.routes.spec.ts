// src/tests/router/public.routes.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';

import { useAuthStore } from '@/shared/stores/authStore';
import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

// Mock stores used by useDomainContext
vi.mock('@/shared/stores/domainsStore', () => ({
  useDomainsStore: () => ({
    domains: [],
    fetchList: vi.fn().mockResolvedValue(undefined),
  }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    currentOrganization: null,
  }),
}));

vi.mock('@/shared/stores/authStore', () => ({
  useAuthStore: vi.fn(() => ({ isAuthenticated: false })),
}));

// Set up Pinia before importing routes (routes use bootstrapStore at module level)
const pinia = createTestingPinia({
  createSpy: vi.fn,
  stubActions: false,
  initialState: {
    bootstrap: {
      authenticated: false,
      domain_strategy: 'canonical',
      site_host: 'onetimesecret.com',
      display_domain: 'onetimesecret.com',
      domains_enabled: false,
      ui: { enabled: true },
      authentication: { required: false },
      homepage_mode: null,
    },
  },
});
setActivePinia(pinia);

// Import routes after Pinia is set up
import publicRoutes, { redirectAuthenticatedToPlans } from '@/router/public.routes';

describe('Public Routes', () => {
  describe('Homepage Route', () => {
    let route: RouteRecordRaw | undefined;

    beforeEach(() => {
      vi.clearAllMocks();
      route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/');
    });

    it('should define homepage route correctly', () => {
      expect(route).toBeDefined();
      expect(route?.name).toBe('Home');
      expect(route?.meta?.requiresAuth).toBe(false);
      expect(route?.meta?.layout).toBeDefined();
    });

    it('should have correct layout props', () => {
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true);
      expect(route?.meta?.layoutProps?.displayFooterLinks).toBe(true);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true);
    });
  });

  // The Home route's beforeEnter guard resolves componentMode. Install-wide
  // authentication.required / homepage_mode gate the CANONICAL site only;
  // custom domains self-govern their homepage via the per-domain
  // HomepageConfig (consumed downstream by BrandedHomepage), so those site
  // flags must not force a custom domain to the disabled-homepage view. The
  // deployment-wide UI kill switch stays global.
  describe('componentMode resolution (site flags vs custom-domain self-governance)', () => {
    let route: RouteRecordRaw | undefined;
    let bootstrapStore: ReturnType<typeof useBootstrapStore>;

    const runBeforeEnter = async () => {
      const to = { meta: { layoutProps: {} } } as unknown as RouteLocationNormalized;
      await (
        route as unknown as { beforeEnter: (to: RouteLocationNormalized) => Promise<void> }
      ).beforeEnter(to);
      return to.meta.componentMode;
    };

    beforeEach(() => {
      vi.clearAllMocks();
      bootstrapStore = useBootstrapStore();
      route = publicRoutes.find((r: RouteRecordRaw) => r.path === '/');
      // No session cookie by default; the site-flag gates only fire for
      // anonymous visitors.
      document.cookie = 'ots-session=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/';
      bootstrapStore.$patch({
        domain_strategy: 'canonical',
        ui: { enabled: true },
        authentication: { required: false },
        homepage_mode: null,
      });
    });

    it('canonical: disables the homepage for anonymous visitors when auth is required', async () => {
      bootstrapStore.$patch({ authentication: { required: true } });
      expect(await runBeforeEnter()).toBe('disabled-homepage');
    });

    it('canonical: disables the homepage for anonymous visitors in external mode', async () => {
      bootstrapStore.$patch({ homepage_mode: 'external' });
      expect(await runBeforeEnter()).toBe('disabled-homepage');
    });

    it('custom: ignores install-wide authentication.required (self-governs via HomepageConfig)', async () => {
      bootstrapStore.$patch({ domain_strategy: 'custom', authentication: { required: true } });
      expect(await runBeforeEnter()).toBe('normal');
    });

    it('custom: ignores install-wide homepage_mode=external', async () => {
      bootstrapStore.$patch({ domain_strategy: 'custom', homepage_mode: 'external' });
      expect(await runBeforeEnter()).toBe('normal');
    });

    it('custom: the deployment-wide UI kill switch still applies', async () => {
      bootstrapStore.$patch({ domain_strategy: 'custom', ui: { enabled: false } });
      expect(await runBeforeEnter()).toBe('disabled-ui');
    });
  });

  // NOTE: Info routes (privacy, terms, security) have been removed and are no longer available

  // NOTE: Feedback route has been removed and is no longer available

  // NOTE: Translations route has been removed and is no longer available

  describe('redirectAuthenticatedToPlans', () => {
    const makeRoute = (
      overrides: Partial<RouteLocationNormalized> = {}
    ): RouteLocationNormalized => ({
      meta: {},
      path: '/pricing',
      name: 'Pricing',
      params: {},
      query: {},
      hash: '',
      fullPath: '/pricing',
      matched: [],
      redirectedFrom: undefined,
      ...overrides,
    });

    const authenticate = (isAuthenticated: boolean) => {
      vi.mocked(useAuthStore).mockReturnValue({
        isAuthenticated,
      } as ReturnType<typeof useAuthStore>);
    };

    beforeEach(() => {
      vi.clearAllMocks();
    });

    it('lets unauthenticated visitors through (returns true)', () => {
      authenticate(false);
      expect(redirectAuthenticatedToPlans(makeRoute())).toBe(true);
    });

    it('redirects authenticated visitors to the plan selector', () => {
      authenticate(true);
      expect(redirectAuthenticatedToPlans(makeRoute())).toEqual({
        path: '/billing/plans',
        query: {},
      });
    });

    it('carries a deep-linked product param through the redirect', () => {
      authenticate(true);
      expect(
        redirectAuthenticatedToPlans(makeRoute({ params: { product: 'pro' } }))
      ).toEqual({ path: '/billing/plans', query: { product: 'pro' } });
    });

    it('maps year-alias intervals (annual/year/yearly) to "yearly"', () => {
      authenticate(true);
      for (const alias of ['annual', 'year', 'yearly', 'ANNUAL']) {
        expect(
          redirectAuthenticatedToPlans(makeRoute({ params: { interval: alias } }))
        ).toEqual({ path: '/billing/plans', query: { interval: 'yearly' } });
      }
    });

    it('maps any non-year interval to "monthly"', () => {
      authenticate(true);
      expect(
        redirectAuthenticatedToPlans(makeRoute({ params: { interval: 'month' } }))
      ).toEqual({ path: '/billing/plans', query: { interval: 'monthly' } });
    });

    it('does not throw on array query params and collapses to the first value', () => {
      authenticate(true);
      // ?interval=annual&interval=monthly arrives as an array; the old code
      // called interval.toLowerCase() on the array and crashed navigation.
      const run = () =>
        redirectAuthenticatedToPlans(
          makeRoute({
            query: {
              product: ['pro', 'team'],
              interval: ['annual', 'monthly'],
            },
          })
        );
      expect(run).not.toThrow();
      expect(run()).toEqual({
        path: '/billing/plans',
        query: { product: 'pro', interval: 'yearly' },
      });
    });
  });
});
