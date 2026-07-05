// src/tests/apps/workspace/routes/dashboard.spec.ts

import dashboardRoutes from '@/apps/workspace/routes/dashboard';
import { isApproximatedDomainValidation } from '@/utils/features';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

// Control the install's validation strategy for the DNS/verify route guards.
vi.mock('@/utils/features', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/utils/features')>()),
  isApproximatedDomainValidation: vi.fn(() => true),
}));
const mockApprox = vi.mocked(isApproximatedDomainValidation);

const findRoute = (name: string) =>
  dashboardRoutes.find((r: RouteRecordRaw) => r.name === name);

/** Invoke a route's single beforeEnter guard with a minimal `to` stub. */
const runGuard = (name: string, params: Record<string, string>) => {
  const guard = findRoute(name)?.beforeEnter;
  if (typeof guard !== 'function') throw new Error(`no beforeEnter on ${name}`);
  return guard({ params } as never, {} as never, (() => {}) as never);
};

describe('Dashboard Routes', () => {
  describe('Dashboard Route', () => {
    it('should define dashboard route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/dashboard');
      expect(route).toBeDefined();
      expect(route?.meta?.requiresAuth).toBe(true);
      // Routes use single component (direct import), not named components
      expect(route?.component).toBeDefined();
      expect(route?.meta?.layout).toBeDefined();
    });
  });

  describe('Recents Route', () => {
    it('should define recents route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/recent');
      expect(route).toBeDefined();
      expect(route?.meta?.requiresAuth).toBe(true);
      // Routes use single component (direct import), not named components
      expect(route?.component).toBeDefined();
      expect(route?.meta?.layout).toBeDefined();
    });
  });

  describe('DomainDns Route', () => {
    it('should define the DNS setup route correctly', () => {
      const route = findRoute('DomainDns');
      expect(route?.path).toBe('/org/:orgid/domains/:extid/dns');
      expect(route?.meta?.requiresAuth).toBe(true);
      expect(route?.meta?.requiresOrgRole).toBe('admin');
      expect(route?.component).toBeDefined();
    });
  });

  describe('DNS / verification route guards', () => {
    const params = { orgid: 'org-1', extid: 'dm-1' };

    beforeEach(() => {
      mockApprox.mockReturnValue(true);
    });

    it('DomainVerify is allowed on approximated installs', () => {
      mockApprox.mockReturnValue(true);
      expect(runGuard('DomainVerify', params)).toBe(true);
    });

    it('DomainVerify redirects to DomainDns on non-approximated installs', () => {
      mockApprox.mockReturnValue(false);
      expect(runGuard('DomainVerify', params)).toEqual({ name: 'DomainDns', params });
    });

    it('DomainDns is allowed on non-approximated installs', () => {
      mockApprox.mockReturnValue(false);
      expect(runGuard('DomainDns', params)).toBe(true);
    });

    it('DomainDns redirects to DomainVerify on approximated installs', () => {
      mockApprox.mockReturnValue(true);
      expect(runGuard('DomainDns', params)).toEqual({ name: 'DomainVerify', params });
    });
  });
});
