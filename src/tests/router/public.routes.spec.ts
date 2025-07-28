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
      expect(route?.meta?.layoutProps?.displayFooterLinks).toBe(true);
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

  // NOTE: Info routes (privacy, terms, security) have been removed and are no longer available

  // NOTE: Feedback route has been removed and is no longer available

  // NOTE: Translations route has been removed and is no longer available
});
