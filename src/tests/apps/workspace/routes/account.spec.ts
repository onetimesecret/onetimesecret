// src/tests/apps/workspace/routes/account.spec.ts

import accountRoutes from '@/apps/workspace/routes/account';
import { describe, expect, it } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

describe('Account Routes', () => {
  describe('Account Route', () => {
    it('should define account route correctly', () => {
      const route = accountRoutes.find(
        (route: RouteRecordRaw) => route.path === '/account'
      );
      expect(route).toBeDefined();
      expect(route?.meta?.requiresAuth).toBe(true);
      expect(route?.components?.default).toBeInstanceOf(Function);
      expect(route?.components?.header).toBeDefined();
      expect(route?.components?.footer).toBeDefined();
    });
  });

  // NOTE: Domain-related routes and Colonel route have been removed and are no longer available
});
