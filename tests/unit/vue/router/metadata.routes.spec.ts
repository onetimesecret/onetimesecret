// tests/unit/vue/router/metadata.routes.spec.ts

import routes from '@/router/metadata.routes';
import { describe, expect, it, vi } from 'vitest';
import { RouteRecordRaw } from 'vue-router';

// Mock the secrets store
vi.mock('@/stores/secretStore', () => ({
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
    it('should define metadata link route correctly', () => {
      const route = routes.find((route: RouteRecordRaw) => route.path === '/receipt/:metadataKey');
      expect(route).toBeDefined();
      expect(route?.meta?.layoutProps?.displayMasthead).toBe(true);
      expect(route?.meta?.layoutProps?.displayNavigation).toBe(true);
      expect(route?.meta?.layoutProps?.displayFooterLinks).toBe(true);
      expect(route?.meta?.layoutProps?.displayFeedback).toBe(true);
      expect(route?.meta?.layoutProps?.displayVersion).toBe(true);
      expect(route?.meta?.layoutProps?.displayPoweredBy).toBe(false);
    });
  });

  describe('Private Link Route (/private)', () => {
    it('should define metadata link route correctly', () => {
      const route = routes.find((route: RouteRecordRaw) => route.path === '/metadata/:metadataKey');
      expect(route).toBeUndefined();
    });
  });

  describe('Metadata Link Route (/metadata)', () => {
    it('should define metadata link route correctly', () => {
      const route = routes.find((route: RouteRecordRaw) => route.path === '/metadata/:metadataKey');
      expect(route).toBeUndefined();
    });
  });

  describe('Burn Secret Route', () => {
    it('should define burn secret route correctly', () => {
      const route = routes.find(
        (route: RouteRecordRaw) => route.path === '/private/:metadataKey/burn'
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
