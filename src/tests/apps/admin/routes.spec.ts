// src/tests/apps/admin/routes.spec.ts

import adminRoutes, { adminDefaultMeta } from '@/apps/admin/routes';
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

    it('registers the customers list route under /colonel (ticket #22)', () => {
      const route = adminRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/customers');
      expect(route).toBeDefined();
      expect(route?.name).toBe('AdminCustomers');
      expect(route?.meta?.title).toBe('web.admin.customers.title');
    });

    it('registers the customer detail route with the public-id param (ticket #22)', () => {
      const route = adminRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/customers/:id');
      expect(route).toBeDefined();
      expect(route?.name).toBe('AdminCustomerDetail');
      // Detail param is forwarded as a prop so the view reads it type-safely.
      expect(route?.props).toBe(true);
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
      // Named 'NotFound' so the shared auth guard's not-found bypass exempts it
      // (the admin router has no /signin route, so a requiresAuth catch-all
      // would trap auth-recovery redirects in a loop).
      expect(names).toContain('NotFound');
    });

    it('navigates to the overview at /colonel', async () => {
      const router = createAdminRouter();
      await router.push('/colonel');
      expect(router.currentRoute.value.name).toBe('AdminOverview');
    });

    it('navigates to the customers list and detail (ticket #22)', async () => {
      const router = createAdminRouter();

      await router.push('/colonel/customers');
      expect(router.currentRoute.value.name).toBe('AdminCustomers');

      await router.push('/colonel/customers/ur_abc123');
      expect(router.currentRoute.value.name).toBe('AdminCustomerDetail');
      expect(router.currentRoute.value.params.id).toBe('ur_abc123');
    });

    it('falls back to the not-found route for unknown admin sub-paths', async () => {
      const router = createAdminRouter();
      await router.push('/colonel/does-not-exist-yet');
      expect(router.currentRoute.value.name).toBe('NotFound');
    });

    it('renders the not-found fallback inside the console shell (AdminLayout)', async () => {
      // The router-injected catch-all is NOT in the adminRoutes array, so the
      // "every route uses AdminLayout" check above cannot cover it. Assert here
      // that an in-console 404 keeps the admin layout rather than escaping to
      // the customer MinimalLayout.
      const router = createAdminRouter();
      await router.push('/colonel/does-not-exist-yet');
      expect(router.currentRoute.value.meta.layout).toBe(adminDefaultMeta.layout);
    });
  });

  describe('Console map', () => {
    it('overview is the live section and points at /colonel', () => {
      const overview = CONSOLE_SECTIONS.find((s) => s.key === 'overview');
      expect(overview?.to).toBe('/colonel');
    });

    it('customers is now a live section pointing at the list route (ticket #22)', () => {
      const customers = CONSOLE_SECTIONS.find((s) => s.key === 'customers');
      expect(customers?.to).toBe('/colonel/customers');
    });

    it('the remaining sections have no route until later phases wire them', () => {
      const liveKeys = new Set(['overview', 'customers']);
      const placeholders = CONSOLE_SECTIONS.filter((s) => !liveKeys.has(s.key));
      expect(placeholders.length).toBeGreaterThan(0);
      placeholders.forEach((s) => expect(s.to).toBeUndefined());
    });
  });
});
