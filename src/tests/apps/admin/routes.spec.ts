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

    it('every console section is now wired to a route (Phase 2 complete)', () => {
      // Phase 2 (tickets #30-33) wires the last placeholder sections: secrets,
      // organizations, domains, system, bannedIps, usage. Every section now
      // points at a live route, and each `to` resolves to a defined route.
      const routePaths = new Set(adminRoutes.map((r: RouteRecordRaw) => r.path));
      CONSOLE_SECTIONS.forEach((s) => {
        expect(s.to).toBeDefined();
        expect(routePaths.has(s.to as string)).toBe(true);
      });
    });

    it('maps each Phase-2 section to its list route', () => {
      const expected: Record<string, string> = {
        secrets: '/colonel/secrets',
        organizations: '/colonel/organizations',
        domains: '/colonel/domains',
        system: '/colonel/system',
        bannedIps: '/colonel/banned-ips',
        usage: '/colonel/usage',
      };
      Object.entries(expected).forEach(([key, path]) => {
        expect(CONSOLE_SECTIONS.find((s) => s.key === key)?.to).toBe(path);
      });
    });
  });

  describe('Phase-2 routes (tickets #30-33)', () => {
    const cases: Array<{ path: string; name: string; title: string }> = [
      { path: '/colonel/secrets', name: 'AdminSecrets', title: 'web.admin.secrets.title' },
      { path: '/colonel/domains', name: 'AdminDomains', title: 'web.colonel.titles.domains' },
      {
        path: '/colonel/organizations',
        name: 'AdminOrganizations',
        title: 'web.colonel.titles.organizations',
      },
      { path: '/colonel/system', name: 'AdminSystem', title: 'web.admin.system.title' },
      { path: '/colonel/banned-ips', name: 'AdminBannedIps', title: 'web.admin.bannedIps.title' },
      { path: '/colonel/usage', name: 'AdminUsage', title: 'web.admin.usage.title' },
    ];

    cases.forEach(({ path, name, title }) => {
      it(`registers the ${name} route at ${path}`, () => {
        const route = adminRoutes.find((r: RouteRecordRaw) => r.path === path);
        expect(route).toBeDefined();
        expect(route?.name).toBe(name);
        expect(route?.meta?.title).toBe(title);
      });
    });
  });

  describe('Phase-3 routes (tickets #40-45)', () => {
    const cases: Array<{ path: string; name: string; title: string; sectionKey: string }> = [
      {
        path: '/colonel/sessions',
        name: 'AdminSessions',
        title: 'web.admin.sessions.title',
        sectionKey: 'sessions',
      },
      {
        path: '/colonel/banner',
        name: 'AdminBanner',
        title: 'web.admin.banner.title',
        sectionKey: 'banner',
      },
      {
        path: '/colonel/queues/dlq',
        name: 'AdminQueueDlq',
        title: 'web.admin.queue.title',
        sectionKey: 'queueDlq',
      },
      {
        path: '/colonel/domain-toolbox',
        name: 'AdminDomainToolbox',
        title: 'web.admin.domaintoolbox.title',
        sectionKey: 'domaintoolbox',
      },
      {
        path: '/colonel/email-tools',
        name: 'AdminEmailTools',
        title: 'web.admin.emailtools.title',
        sectionKey: 'emailTools',
      },
      {
        path: '/colonel/billing',
        name: 'AdminBilling',
        title: 'web.admin.billing.title',
        sectionKey: 'billing',
      },
    ];

    cases.forEach(({ path, name, title, sectionKey }) => {
      it(`registers the ${name} route at ${path}`, () => {
        const route = adminRoutes.find((r: RouteRecordRaw) => r.path === path);
        expect(route).toBeDefined();
        expect(route?.name).toBe(name);
        expect(route?.meta?.title).toBe(title);
      });

      it(`${sectionKey} is a live section pointing at ${path}`, () => {
        expect(CONSOLE_SECTIONS.find((s) => s.key === sectionKey)?.to).toBe(path);
      });
    });
  });
});
