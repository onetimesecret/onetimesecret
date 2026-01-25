// src/tests/apps/session/routes.spec.ts

import authRoutes from '@/apps/session/routes';
import { useAuthStore } from '@/shared/stores/authStore';
import { setupRouter } from '@/tests/utils/routerSetup';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteLocationNormalized, RouteRecordRaw } from 'vue-router';

describe('Auth Routes Configuration', () => {
  let router: any;

  beforeEach(() => {
    setActivePinia(createPinia());
    router = setupRouter();
    // Add auth routes to test router
    authRoutes.forEach((route: RouteRecordRaw) => router.addRoute(route));
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Route Definitions', () => {
    it('should define signin route correctly', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/signin');
      expect(route).toBeDefined();
      expect(route?.meta?.requiresAuth).toBe(false);
      expect(route?.meta?.layout).toBeDefined();
      expect(route?.meta?.layoutProps).toBeDefined(); // Ensure layoutProps is defined
      // Type assertion to avoid TS2339 error
      expect((route?.meta?.layoutProps as any).displayMasthead).toBe(false);
    });

    it('should define signup routes with correct children', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/signup');
      expect(route?.children).toHaveLength(2);
      expect(route?.children?.[0].path).toBe('');
      expect(route?.children?.[1].path).toBe(':planCode');
      expect(route?.meta?.requiresAuth).toBe(false);
    });

    it('should define forgot password route correctly', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/forgot');
      expect(route).toBeDefined();
      expect(route?.name).toBe('Forgot Password');
      expect(route?.meta?.requiresAuth).toBe(false);
      expect((route?.meta?.layoutProps as any).displayNavigation).toBe(false);
    });
  });

  describe('Route Component Loading', () => {
    it('should lazy load signin component', async () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/signin');
      expect(typeof route?.component).toBe('function');

      // Test component loading
      const component = await (route?.component as Function)();
      expect(component).toBeDefined();
    });

    it('should lazy load signup components', async () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/signup');
      const mainComponent = await (route?.children?.[0].component as Function)();

      expect(mainComponent).toBeDefined();
    });
  });

  describe('Logout Route', () => {
    it('should have correct logout route configuration', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/logout');
      expect(route?.meta?.requiresAuth).toBe(true);
      expect(route?.meta?.layout).toBeDefined();
      expect(route?.beforeEnter).toBeDefined();
    });

    it('should handle successful logout', async () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/logout');
      const authStore = useAuthStore();
      const logoutSpy = vi.spyOn(authStore, 'logout').mockResolvedValue();

      // Mock window.location
      const originalLocation = window.location;
      const mockLocation = { href: '' } as Location;
      Object.defineProperty(window, 'location', {
        value: mockLocation,
        writable: true,
      });

      // Execute beforeEnter guard
      const beforeEnterGuard = Array.isArray(route?.beforeEnter)
        ? route?.beforeEnter[0]
        : route?.beforeEnter;
      await beforeEnterGuard?.call(
        undefined,
        {} as RouteLocationNormalized,
        {} as RouteLocationNormalized,
        vi.fn(() => {})
      );

      expect(logoutSpy).toHaveBeenCalled();
      expect(window.location.href).toBe('/logout');

      // Restore window.location
      Object.defineProperty(window, 'location', {
        value: originalLocation,
        writable: true,
      });
    });

    it('should handle logout failure', async () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/logout');
      const authStore = useAuthStore();
      const error = new Error('Logout failed');
      const logoutSpy = vi.spyOn(authStore, 'logout').mockRejectedValue(error);
      const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

      // Mock window.location
      const originalLocation = window.location;
      const mockLocation = { href: '' } as Location;
      Object.defineProperty(window, 'location', {
        value: mockLocation,
        writable: true,
      });

      const beforeEnterGuard = Array.isArray(route?.beforeEnter)
        ? route?.beforeEnter[0]
        : route?.beforeEnter;
      await beforeEnterGuard?.call(
        undefined,
        {} as RouteLocationNormalized,
        {} as RouteLocationNormalized,
        vi.fn(() => {})
      );

      expect(logoutSpy).toHaveBeenCalled();
      expect(consoleSpy).toHaveBeenCalledWith('Logout failed:', error);
      expect(window.location.href).toBe('/logout');

      // Restore window.location
      Object.defineProperty(window, 'location', {
        value: originalLocation,
        writable: true,
      });
    });
  });

  describe('Route Navigation', () => {
    it('should navigate to signin page', async () => {
      await router.push('/signin');
      expect(router.currentRoute.value.path).toBe('/signin');
    });

    it('should navigate to signup', async () => {
      await router.push('/signup');
      expect(router.currentRoute.value.path).toBe('/signup');
    });

    it('should navigate to password reset with reset key', async () => {
      const resetKey = 'abc123';
      await router.push(`/reset-password?key=${resetKey}`);
      expect(router.currentRoute.value.path).toBe('/reset-password');
      expect(router.currentRoute.value.query.key).toBe(resetKey);
    });
  });

  describe('Layout Props', () => {
    it('should have correct layout props for signin', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/signin');
      expect(route?.meta?.layoutProps).toEqual({
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      });
    });

    it('should have correct layout props for signup', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/signup');
      expect(route?.meta?.layoutProps).toEqual({
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
      });
    });

    it('should have correct layout props for forgot password', () => {
      const route = authRoutes.find((route: RouteRecordRaw) => route.path === '/forgot');
      expect(route?.meta?.layoutProps).toEqual({
        displayMasthead: false,
        displayNavigation: false,
        displayFooterLinks: false,
        displayFeedback: false,
        displayVersion: true,
        displayToggles: true,
      });
    });
  });
});
