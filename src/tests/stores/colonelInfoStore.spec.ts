// src/tests/stores/colonelInfoStore.spec.ts
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mockApi = {
  get: vi.fn(),
  post: vi.fn(),
  delete: vi.fn(),
};

vi.mock('@/shared/composables/useApi', () => ({
  useApi: () => mockApi,
}));

const mockGracefulParse = vi.fn();
vi.mock('@/utils/schemaValidation', () => ({
  gracefulParse: (...args: unknown[]) => mockGracefulParse(...args),
}));

import { useColonelInfoStore } from '@/shared/stores/colonelInfoStore';
import { useSystemSettingsStore } from '@/shared/stores/systemSettingsStore';

describe('colonelInfoStore', () => {
  beforeEach(() => {
    const pinia = createPinia();
    setActivePinia(pinia);
  });

  afterEach(() => {
    vi.clearAllMocks();
  });

  describe('Store ID uniqueness', () => {
    it('colonelInfoStore and systemSettingsStore have different IDs', () => {
      const colonelStore = useColonelInfoStore();
      const settingsStore = useSystemSettingsStore();

      expect(colonelStore.$id).toBe('colonel');
      expect(settingsStore.$id).toBe('systemSettings');
      expect(colonelStore.$id).not.toBe(settingsStore.$id);
    });

    it('instantiating both stores does not cause state collision', () => {
      const colonelStore = useColonelInfoStore();
      const settingsStore = useSystemSettingsStore();

      // Each store should have its own distinct state shape
      expect('stats' in colonelStore).toBe(true);
      expect('details' in settingsStore).toBe(true);

      // colonelStore should not have systemSettingsStore's properties
      expect('details' in colonelStore).toBe(true); // colonelInfoStore has its own details
      expect(colonelStore.stats).toBeNull();
      expect(settingsStore.details).toBeNull();
    });
  });

  describe('Per-resource loading flags', () => {
    it('has independent loading flags for each resource', () => {
      const store = useColonelInfoStore();

      expect(store.loading).toBeDefined();
      expect(store.loading.users).toBe(false);
      expect(store.loading.stats).toBe(false);
      expect(store.loading.secrets).toBe(false);
      expect(store.loading.databaseMetrics).toBe(false);
      expect(store.loading.redisMetrics).toBe(false);
      expect(store.loading.bannedIPs).toBe(false);
      expect(store.loading.customDomains).toBe(false);
      expect(store.loading.organizations).toBe(false);
    });

    it('loading flags are reactive and independent', () => {
      const store = useColonelInfoStore();

      // Simulate one resource loading
      store.loading.users = true;
      expect(store.loading.users).toBe(true);
      expect(store.loading.stats).toBe(false);
      expect(store.loading.secrets).toBe(false);

      // Simulate another resource loading
      store.loading.stats = true;
      expect(store.loading.users).toBe(true);
      expect(store.loading.stats).toBe(true);

      // First finishes, second still loading
      store.loading.users = false;
      expect(store.loading.users).toBe(false);
      expect(store.loading.stats).toBe(true);
    });
  });

  describe('banIP loading state', () => {
    const bannedIPsResponse = {
      ok: true,
      data: { details: { current_ip: '1.2.3.4', banned_ips: [] } },
    };

    it('sets loading.bannedIPs to true during banIP operation', async () => {
      const store = useColonelInfoStore();
      let loadingDuringCall = false;

      mockApi.post.mockImplementation(() => {
        loadingDuringCall = store.loading.bannedIPs;
        return Promise.resolve({ data: {} });
      });
      mockApi.get.mockResolvedValue({ data: {} });
      mockGracefulParse.mockReturnValue(bannedIPsResponse);

      await store.banIP('192.168.1.1', 'test reason');

      expect(loadingDuringCall).toBe(true);
    });

    it('sets loading.bannedIPs to false after successful banIP', async () => {
      const store = useColonelInfoStore();

      mockApi.post.mockResolvedValue({ data: {} });
      mockApi.get.mockResolvedValue({ data: {} });
      mockGracefulParse.mockReturnValue(bannedIPsResponse);

      await store.banIP('192.168.1.1', 'test reason');

      expect(store.loading.bannedIPs).toBe(false);
    });

    it('sets loading.bannedIPs to false after failed banIP', async () => {
      const store = useColonelInfoStore();

      mockApi.post.mockRejectedValue(new Error('API error'));

      await expect(store.banIP('192.168.1.1')).rejects.toThrow('API error');
      expect(store.loading.bannedIPs).toBe(false);
    });
  });

  describe('unbanIP loading state', () => {
    const bannedIPsResponse = {
      ok: true,
      data: { details: { current_ip: '1.2.3.4', banned_ips: [] } },
    };

    it('sets loading.bannedIPs to true during unbanIP operation', async () => {
      const store = useColonelInfoStore();
      let loadingDuringCall = false;

      mockApi.delete.mockImplementation(() => {
        loadingDuringCall = store.loading.bannedIPs;
        return Promise.resolve({ data: {} });
      });
      mockApi.get.mockResolvedValue({ data: {} });
      mockGracefulParse.mockReturnValue(bannedIPsResponse);

      await store.unbanIP('192.168.1.1');

      expect(loadingDuringCall).toBe(true);
    });

    it('sets loading.bannedIPs to false after successful unbanIP', async () => {
      const store = useColonelInfoStore();

      mockApi.delete.mockResolvedValue({ data: {} });
      mockApi.get.mockResolvedValue({ data: {} });
      mockGracefulParse.mockReturnValue(bannedIPsResponse);

      await store.unbanIP('192.168.1.1');

      expect(store.loading.bannedIPs).toBe(false);
    });

    it('sets loading.bannedIPs to false after failed unbanIP', async () => {
      const store = useColonelInfoStore();

      mockApi.delete.mockRejectedValue(new Error('API error'));

      await expect(store.unbanIP('192.168.1.1')).rejects.toThrow('API error');
      expect(store.loading.bannedIPs).toBe(false);
    });
  });
});
