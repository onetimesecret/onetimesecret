// tests/unit/vue/stores/incomingStore.spec.ts

import { useIncomingStore } from '@/stores/incomingStore';
import { IncomingConfig, IncomingSecretPayload } from '@/schemas/api/incoming';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App, ComponentPublicInstance } from 'vue';
import { AxiosInstance } from 'axios';
import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

const mockIncomingConfig: IncomingConfig = {
  enabled: true,
  memo_max_length: 50,
  recipients: [
    { hash: 'hash123abc', name: 'John Doe' },
    { hash: 'hash456def', name: 'Jane Smith' },
  ],
  default_ttl: 604800,
};

const mockIncomingSecretResponse = {
  success: true,
  message: 'Secret created successfully',
  metadata_key: 'metadata123',
  secret_key: 'secret456',
};

describe('incomingStore', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let appInstance: ComponentPublicInstance | null;
  let store: ReturnType<typeof useIncomingStore>;

  beforeEach(async () => {
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    appInstance = setup.appInstance;

    axiosMock = new AxiosMockAdapter(api);

    const windowMock = setupWindowState({ shrimp: undefined });
    vi.stubGlobal('window', windowMock);

    store = useIncomingStore();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    if (axiosMock) axiosMock.reset();
  });

  describe('Initialization', () => {
    it('initializes with null config', () => {
      expect(store.config).toBeNull();
      expect(store.isConfigLoading).toBe(false);
      expect(store.configError).toBeNull();
      expect(store.isFeatureEnabled).toBe(false);
    });

    it('initializes correctly via init method', () => {
      const result = store.init();
      expect(result.isInitialized).toBe(true);
      expect(store.isInitialized).toBe(true);
    });

    it('does not reinitialize if already initialized', () => {
      store.init();
      const result = store.init();
      expect(result.isInitialized).toBe(true);
    });
  });

  describe('loadConfig', () => {
    it('loads configuration successfully', async () => {
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, mockIncomingConfig);

      const config = await store.loadConfig();

      expect(config).toEqual(mockIncomingConfig);
      expect(store.config).toEqual(mockIncomingConfig);
      expect(store.isConfigLoading).toBe(false);
      expect(store.configError).toBeNull();
    });

    it('sets loading state during config fetch', async () => {
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, mockIncomingConfig);

      const loadPromise = store.loadConfig();
      expect(store.isConfigLoading).toBe(true);

      await loadPromise;
      expect(store.isConfigLoading).toBe(false);
    });

    it('handles config loading errors', async () => {
      axiosMock?.onGet('/api/v2/incoming/config').reply(500, { message: 'Server error' });

      await expect(store.loadConfig()).rejects.toThrow();
      expect(store.configError).toBeTruthy();
      expect(store.isConfigLoading).toBe(false);
    });

    it('validates config response schema', async () => {
      const invalidConfig = { enabled: 'not-a-boolean' };
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, invalidConfig);

      await expect(store.loadConfig()).rejects.toThrow();
    });
  });

  describe('Getters', () => {
    beforeEach(async () => {
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, mockIncomingConfig);
      await store.loadConfig();
    });

    it('returns correct isFeatureEnabled', () => {
      expect(store.isFeatureEnabled).toBe(true);
    });

    it('returns correct memoMaxLength', () => {
      expect(store.memoMaxLength).toBe(50);
    });

    it('returns correct recipients', () => {
      expect(store.recipients).toEqual(mockIncomingConfig.recipients);
    });

    it('returns correct defaultTtl', () => {
      expect(store.defaultTtl).toBe(604800);
    });

    it('returns default values when config is null', () => {
      store.clear();
      expect(store.isFeatureEnabled).toBe(false);
      expect(store.memoMaxLength).toBe(50);
      expect(store.recipients).toEqual([]);
    });
  });

  describe('createIncomingSecret', () => {
    const mockPayload: IncomingSecretPayload = {
      memo: 'Test Secret',
      secret: 'my secret content',
      recipient: 'hash123abc',
    };

    beforeEach(async () => {
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, mockIncomingConfig);
      await store.loadConfig();
    });

    it('creates incoming secret successfully', async () => {
      axiosMock?.onPost('/api/v2/incoming/secret').reply(200, mockIncomingSecretResponse);

      const response = await store.createIncomingSecret(mockPayload);

      expect(response).toEqual(mockIncomingSecretResponse);
      expect(response.success).toBe(true);
      expect(response.metadata_key).toBe('metadata123');
    });

    it('throws error when feature is disabled', async () => {
      const disabledConfig = { ...mockIncomingConfig, enabled: false };
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, disabledConfig);
      await store.loadConfig();

      await expect(store.createIncomingSecret(mockPayload)).rejects.toThrow(
        'Incoming secrets feature is not enabled'
      );
    });

    it('handles secret creation errors', async () => {
      axiosMock?.onPost('/api/v2/incoming/secret').reply(400, { message: 'Invalid payload' });

      await expect(store.createIncomingSecret(mockPayload)).rejects.toThrow();
    });

    it('validates response schema', async () => {
      const invalidResponse = { success: 'not-a-boolean' };
      axiosMock?.onPost('/api/v2/incoming/secret').reply(200, invalidResponse);

      await expect(store.createIncomingSecret(mockPayload)).rejects.toThrow();
    });

    it('sends correct payload to API', async () => {
      axiosMock?.onPost('/api/v2/incoming/secret').reply((config) => {
        const data = JSON.parse(config.data);
        expect(data.secret).toEqual(mockPayload);
        return [200, mockIncomingSecretResponse];
      });

      await store.createIncomingSecret(mockPayload);
    });
  });

  describe('clear', () => {
    it('clears all state', async () => {
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, mockIncomingConfig);
      await store.loadConfig();

      store.clear();

      expect(store.config).toBeNull();
      expect(store.configError).toBeNull();
      expect(store.isConfigLoading).toBe(false);
    });
  });

  describe('$reset', () => {
    it('resets store to initial state', async () => {
      store.init();
      axiosMock?.onGet('/api/v2/incoming/config').reply(200, mockIncomingConfig);
      await store.loadConfig();

      store.$reset();

      expect(store.config).toBeNull();
      expect(store.configError).toBeNull();
      expect(store.isConfigLoading).toBe(false);
      expect(store._initialized).toBe(false);
    });
  });
});
