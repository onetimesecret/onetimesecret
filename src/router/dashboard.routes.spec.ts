import dashboardRoutes from '@/router/dashboard.routes';
import { describe, expect, it } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

describe('Dashboard Routes', () => {
  describe('Dashboard Route', () => {
    it('should define dashboard route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/dashboard');
      expect(route).toBeDefined();
      expect(route?.meta?.requiresAuth).toBe(true);
      expect(typeof route?.components?.default).toBe('object'); // Check for object type
      expect(route?.components?.header).toBeDefined();
      expect(route?.components?.footer).toBeDefined();
    });
  });

  describe('Recents Route', () => {
    it('should define recents route correctly', () => {
      const route = dashboardRoutes.find((route: RouteRecordRaw) => route.path === '/recent');
      expect(route).toBeDefined();
      expect(route?.meta?.requiresAuth).toBe(true);
      expect(typeof route?.components?.default).toBe('object'); // Check for object type
      expect(route?.components?.header).toBeDefined();
      expect(route?.components?.footer).toBeDefined();
    });
  });
});
