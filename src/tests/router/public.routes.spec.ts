// src/tests/router/public.routes.spec.ts

import { createTestingPinia } from '@pinia/testing';
import { setActivePinia } from 'pinia';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

import { useBootstrapStore } from '@/shared/stores/bootstrapStore';

// Mock stores used by useDomainScope
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
import publicRoutes from '@/router/public.routes';

describe('Public Routes', () => {
  describe('Homepage Route', () => {
    let route: RouteRecordRaw | undefined;
    let bootstrapStore: ReturnType<typeof useBootstrapStore>;

    beforeEach(() => {
      vi.clearAllMocks();
      bootstrapStore = useBootstrapStore();
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

  // NOTE: Info routes (privacy, terms, security) have been removed and are no longer available

  // NOTE: Feedback route has been removed and is no longer available

  // NOTE: Translations route has been removed and is no longer available
});
