// src/tests/router/public.routes.spec.ts

import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

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

// Mock WindowService with all required methods
vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn(),
    getMultiple: vi.fn().mockReturnValue({
      domains_enabled: false,
      site_host: 'onetimesecret.com',
      display_domain: 'onetimesecret.com',
    }),
  },
}));

// Import routes after the mock is set up
import publicRoutes from '@/router/public.routes';

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

  // NOTE: Info routes (privacy, terms, security) have been removed and are no longer available

  // NOTE: Feedback route has been removed and is no longer available

  // NOTE: Translations route has been removed and is no longer available
});
