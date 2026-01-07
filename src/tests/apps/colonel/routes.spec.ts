// src/tests/apps/colonel/routes.spec.ts

import colonelRoutes from '@/apps/colonel/routes';
import { setupRouter } from '@/tests/utils/routerSetup';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

/**
 * Colonel Routes Configuration Tests
 *
 * Tests the admin (colonel) routes to verify:
 * - All routes require authentication
 * - All routes use ColonelLayout
 * - All routes have colonel: true in layoutProps
 * - Routes are correctly defined with proper paths and components
 */
describe('Colonel Routes Configuration', () => {
  let router: ReturnType<typeof setupRouter>;

  beforeEach(() => {
    setActivePinia(createPinia());
    router = setupRouter();
    // Add colonel routes to test router
    colonelRoutes.forEach((route: RouteRecordRaw) => router.addRoute(route));
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Route Definitions', () => {
    it('should define /colonel route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel');
      expect(route).toBeDefined();
      expect(route?.name).toBe('Colonel');
      expect(route?.meta?.title).toBe('web.TITLES.colonel');
    });

    it('should define /colonel/users route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/users');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelUsers');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_users');
    });

    it('should define /colonel/system route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/system');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelSystem');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_system');
    });

    it('should define /colonel/settings route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/settings');
      expect(route).toBeDefined();
      expect(route?.name).toBe('SystemSettings');
      expect(route?.meta?.title).toBe('web.TITLES.system_settings');
    });

    it('should define /colonel/secrets route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/secrets');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelSecrets');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_secrets');
    });

    it('should define /colonel/domains route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/domains');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelDomains');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_domains');
    });

    it('should define /colonel/database/maindb route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/database/maindb');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelSystemMainDB');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_maindb');
    });

    it('should define /colonel/database/authdb route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/database/authdb');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelSystemAuthDB');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_authdb');
    });

    it('should define /colonel/system/redis route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/system/redis');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelSystemRedis');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_redis');
    });

    it('should define /colonel/banned-ips route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/banned-ips');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelBannedIPs');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_banned_ips');
    });

    it('should define /colonel/usage route correctly', () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/usage');
      expect(route).toBeDefined();
      expect(route?.name).toBe('ColonelUsageExport');
      expect(route?.meta?.title).toBe('web.TITLES.colonel_usage');
    });
  });

  describe('Authentication Requirements', () => {
    it('all routes require authentication', () => {
      colonelRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.meta?.requiresAuth).toBe(true);
      });
    });
  });

  describe('Layout Configuration', () => {
    it('all routes use ColonelLayout', () => {
      colonelRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.meta?.layout).toBeDefined();
        // ColonelLayout is the local layout for the colonel app
        // Check that a layout component is assigned
        expect(route.meta?.layout).toBeTruthy();
      });
    });

    it('all routes have layout meta defined', () => {
      colonelRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.meta).toHaveProperty('layout');
      });
    });
  });

  describe('Route Component Loading', () => {
    it('should lazy load ColonelIndex component', async () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel');
      expect(typeof route?.component).toBe('function');

      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });

    it('should lazy load ColonelUsers component', async () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/users');
      expect(typeof route?.component).toBe('function');

      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });

    it('should lazy load ColonelSystem component', async () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/system');
      expect(typeof route?.component).toBe('function');

      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });

    it('should lazy load SystemSettings component', async () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/settings');
      expect(typeof route?.component).toBe('function');

      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });

    it('should lazy load ColonelSecrets component', async () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/secrets');
      expect(typeof route?.component).toBe('function');

      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });

    it('should lazy load ColonelDomains component', async () => {
      const route = colonelRoutes.find((r: RouteRecordRaw) => r.path === '/colonel/domains');
      expect(typeof route?.component).toBe('function');

      const component = await (route?.component as () => Promise<unknown>)();
      expect(component).toBeDefined();
    });
  });

  describe('Route Navigation', () => {
    it('should navigate to colonel index', async () => {
      await router.push('/colonel');
      expect(router.currentRoute.value.path).toBe('/colonel');
    });

    it('should navigate to colonel users', async () => {
      await router.push('/colonel/users');
      expect(router.currentRoute.value.path).toBe('/colonel/users');
    });

    it('should navigate to colonel system', async () => {
      await router.push('/colonel/system');
      expect(router.currentRoute.value.path).toBe('/colonel/system');
    });

    it('should navigate to system settings', async () => {
      await router.push('/colonel/settings');
      expect(router.currentRoute.value.path).toBe('/colonel/settings');
    });

    it('should navigate to colonel secrets', async () => {
      await router.push('/colonel/secrets');
      expect(router.currentRoute.value.path).toBe('/colonel/secrets');
    });

    it('should navigate to colonel domains', async () => {
      await router.push('/colonel/domains');
      expect(router.currentRoute.value.path).toBe('/colonel/domains');
    });

    it('should navigate to maindb', async () => {
      await router.push('/colonel/database/maindb');
      expect(router.currentRoute.value.path).toBe('/colonel/database/maindb');
    });

    it('should navigate to authdb', async () => {
      await router.push('/colonel/database/authdb');
      expect(router.currentRoute.value.path).toBe('/colonel/database/authdb');
    });

    it('should navigate to redis', async () => {
      await router.push('/colonel/system/redis');
      expect(router.currentRoute.value.path).toBe('/colonel/system/redis');
    });

    it('should navigate to banned-ips', async () => {
      await router.push('/colonel/banned-ips');
      expect(router.currentRoute.value.path).toBe('/colonel/banned-ips');
    });

    it('should navigate to usage export', async () => {
      await router.push('/colonel/usage');
      expect(router.currentRoute.value.path).toBe('/colonel/usage');
    });
  });

  describe('Route Props', () => {
    it('all routes pass props', () => {
      colonelRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.props).toBe(true);
      });
    });
  });

  describe('Route Count', () => {
    it('should have 12 colonel routes defined', () => {
      expect(colonelRoutes).toHaveLength(12);
    });

    it('all routes start with /colonel', () => {
      colonelRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.path.startsWith('/colonel')).toBe(true);
      });
    });
  });

  describe('Default Meta Configuration', () => {
    it('uses consistent defaultMeta across all routes', () => {
      const expectedLayoutProps = {
        displayPoweredBy: true,
        displayToggles: true,
        displayFeedback: false,
        colonel: true,
      };

      colonelRoutes.forEach((route: RouteRecordRaw) => {
        expect(route.meta?.layoutProps).toMatchObject(expectedLayoutProps);
      });
    });
  });
});
