// src/tests/apps/admin/routes.spec.ts

import adminRoutes from '@/apps/admin/routes';
import { createAdminRouter } from '@/apps/admin/router';
import { CONSOLE_SECTIONS } from '@/apps/admin/console-sections';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

/**
 * Admin (rebuilt Colonel console) Routes Configuration Tests
 *
 * Phase-0 scaffold: the admin app ships one live route (the Overview) served
 * from its own isolated bundle. These tests verify the route config and that
 * createAdminRouter builds an admin-only router with a not-found fallback —
 * WITHOUT pulling the customer route graph.
 */
describe('Admin Routes Configuration', () => {
  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Route Definitions', () => {
    it('serves the console at the same /colonel URL as the legacy app (D1)', () => {
      const route = adminRoutes.find((r: RouteRecordRaw) => r.path === '/colonel');
      expect(route).toBeDefined();
      expect(route?.name).toBe('AdminOverview');
      expect(route?.meta?.title).toBe('web.colonel.titles.index');
    });

    it('every route requires authentication', () => {
      adminRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.meta?.requiresAuth).toBe(true);
      });
    });

    it('every route uses AdminLayout and suppresses customer chrome', () => {
      adminRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.meta?.layout).toBeTruthy();
        expect(route.meta?.layoutProps).toMatchObject({
          displayMasthead: false,
          displayNavigation: false,
          displayHeader: false,
        });
      });
    });

    it('lazy-loads the AdminOverview component', async () => {
      const route = adminRoutes.find((r: RouteRecordRaw) => r.path === '/colonel');
      expect(typeof route?.component).toBe('function');
      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });
  });

  describe('createAdminRouter', () => {
    beforeEach(() => {
      setActivePinia(createPinia());
    });

    it('registers the admin routes plus a catch-all not-found', () => {
      const router = createAdminRouter();
      const names = router.getRoutes().map((r) => r.name);
      expect(names).toContain('AdminOverview');
      expect(names).toContain('AdminNotFound');
    });

    it('navigates to the overview at /colonel', async () => {
      const router = createAdminRouter();
      await router.push('/colonel');
      expect(router.currentRoute.value.name).toBe('AdminOverview');
    });

    it('falls back to the not-found route for unknown admin sub-paths', async () => {
      const router = createAdminRouter();
      await router.push('/colonel/does-not-exist-yet');
      expect(router.currentRoute.value.name).toBe('AdminNotFound');
    });
  });

  describe('Console map', () => {
    it('overview is the live section and points at /colonel', () => {
      const overview = CONSOLE_SECTIONS.find((s) => s.key === 'overview');
      expect(overview?.to).toBe('/colonel');
    });

    it('placeholder sections have no route until later phases wire them', () => {
      const placeholders = CONSOLE_SECTIONS.filter((s) => s.key !== 'overview');
      expect(placeholders.length).toBeGreaterThan(0);
      placeholders.forEach((s) => expect(s.to).toBeUndefined());
    });
  });
});
