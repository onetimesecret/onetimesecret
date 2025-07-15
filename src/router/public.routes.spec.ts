import { beforeEach, describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

// Move the mock before the route import

vi.mock('@/services/window.service', () => ({
  WindowService: {
    get: vi.fn(),
  },
}));

// Import routes after the mock is set up
import publicRoutes from '@/router/public.routes';

describe('Public Routes', () => {
  describe('Homepage Route', () => {
    it('should define homepage route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/');
      expect(route).toBeDefined();
      expect(route?.name).toBe('Home');
      expect(route?.meta?.requiresAuth).toBe(false);
      expect(route?.meta?.layout).toBeDefined();
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true);
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true);
    });

    // Add beforeEach to clear mocks if needed
    beforeEach(() => {
      vi.clearAllMocks();
    });
  });
  describe('Incoming Secrets Route', () => {
    it('should define incoming secrets route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/incoming');
      expect(route).toBeDefined();
      expect(route?.name).toBe('Inbound Secrets');
      expect(route?.meta?.requiresAuth).toBe(false);
      expect(route?.meta?.layout).toBeDefined();
    });
  });

  describe('Info Routes', () => {
    const infoRoutes = [
      { path: '/info/privacy', name: 'Privacy Policy' },
      { path: '/info/terms', name: 'Terms of Use' },
      { path: '/info/security', name: 'Security Policy' },
    ];

    infoRoutes.forEach((infoRoute) => {
      it(`should define ${infoRoute.name} route correctly`, () => {
        const route = publicRoutes.find((route: RouteRecordRaw) => route.path === infoRoute.path);
        expect(route).toBeDefined();
        expect(route?.name).toBe(infoRoute.name);
        expect(route?.meta?.requiresAuth).toBe(false);
        expect(route?.meta?.layout).toBeDefined();
        expect(typeof route?.component).toBe('function'); // Lazy loaded
      });
    });
  });

  describe('Feedback Route', () => {
    it('should define feedback route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/feedback');
      expect(route).toBeDefined();
      expect(route?.name).toBe('Feedback');
      expect(route?.meta?.requiresAuth).toBe(false);
      expect(route?.meta?.layout).toBeDefined();
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true);
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(false);
      expect(typeof route?.component).toBe('function'); // Lazy loaded
    });
  });

  describe('Translations Route', () => {
    it('should define translations route correctly', () => {
      const route = publicRoutes.find((route: RouteRecordRaw) => route.path === '/translations');
      expect(route).toBeDefined();
      expect(route?.name).toBe('Translations');
      expect(route?.meta?.requiresAuth).toBe(false);
      expect(route?.meta?.layout).toBeDefined();
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true);
      expect(route?.meta?.layoutProps?.displayLinks).toBe(true);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true);
      expect(typeof route?.component).toBe('function'); // Lazy loaded
    });
  });
});
