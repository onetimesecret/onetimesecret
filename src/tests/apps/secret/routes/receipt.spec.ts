// src/tests/apps/secret/routes/receipt.spec.ts

import routes from '@/apps/secret/routes/receipt';
import { describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

// Mock the secrets store
vi.mock('@/shared/stores/secretStore', () => ({
  useSecretStore: vi.fn(() => ({
    fetch: vi.fn().mockResolvedValue({
      record: {
        key: 'test123',
        // ... other record fields
      },
      details: {
        // ... details fields
      },
    }),
  })),
}));

describe('Receipt Routes', () => {
  describe('Receipt Link Route (/receipt)', () => {
    it('should define receipt link route correctly', () => {
      const route = routes.find(
        (route: RouteRecordRaw) => route.path === '/receipt/:receiptIdentifier'
      );
      expect(route).toBeDefined();
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true);
      expect(route?.meta?.layoutProps?.displayNavigation).toBe(true);
      expect(route?.meta?.layoutProps?.displayFooterLinks).toBe(true);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true);
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true);
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(false);
    });
  });

  describe('Legacy Private Link Route (/private)', () => {
    it('should not define legacy private route', () => {
      const route = routes.find(
        (route: RouteRecordRaw) => route.path === '/metadata/:receiptIdentifier'
      );
      expect(route).toBeUndefined();
    });
  });

  describe('Legacy Metadata Route (/metadata)', () => {
    it('should not define legacy /metadata route', () => {
      const route = routes.find(
        (route: RouteRecordRaw) => route.path === '/metadata/:receiptIdentifier'
      );
      expect(route).toBeUndefined();
    });
  });

  describe('Burn Secret Route', () => {
    it('should define burn secret route correctly', () => {
      const route = routes.find(
        (route: RouteRecordRaw) => route.path === '/receipt/:receiptIdentifier/burn'
      );
      expect(route).toBeDefined();
      expect(route?.meta?.layout).toBeDefined();
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(false);
      expect(route?.meta?.layoutProps?.displayNavigation).toBe(false);
      expect(route?.meta?.layoutProps?.displayFooterLinks).toBe(false);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(false);
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true);
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(true);
    });
  });
});
