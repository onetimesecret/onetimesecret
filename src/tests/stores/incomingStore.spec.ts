// src/tests/stores/incomingStore.spec.ts

import {
  incomingConfigSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';
import { useIncomingStore } from '@/shared/stores/incomingStore';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setupTestPinia } from '../setup';

describe('incomingStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useIncomingStore>;

  // Valid mock config matching incomingConfigSchema
  const mockConfig = {
    enabled: true,
    memo_max_length: 100,
    recipients: [
      { hash: 'abc123hash', name: 'Alice' },
      { hash: 'def456hash', name: 'Bob' },
    ],
    default_ttl: 86400,
  };

  // Valid mock response matching incomingSecretResponseSchema
  const mockSecretResponse = {
    success: true,
    message: 'Secret created',
    shrimp: 'shrimp-token',
    custid: 'cust-123',
    record: {
      receipt: {
        identifier: 'receipt-id-123',
        key: 'receipt-key-123',
        custid: 'cust-123',
        owner_id: 'owner-123',
        state: 'new',
        secret_shortid: 'secret-short-123',
        shortid: 'receipt-short-123',
        memo: 'Test memo',
        recipients: 'alice@example.com',
        secret_ttl: 86400,
        receipt_ttl: 86400,
        lifespan: 86400,
        share_domain: 'example.com',
        created: 1700000000,
        updated: 1700000000,
        shared: null,
        received: null,
        burned: null,
        viewed: null,
        show_recipients: true,
        is_viewed: false,
        is_received: false,
        is_burned: false,
        is_expired: false,
        is_orphaned: false,
        is_destroyed: false,
        has_passphrase: false,
      },
      secret: {
        identifier: 'secret-id-123',
        key: 'secret-key-123',
        state: 'new',
        shortid: 'secret-short-123',
        secret_ttl: 86400,
        lifespan: 86400,
        has_passphrase: false,
        verification: false,
        created: 1700000000,
        updated: 1700000000,
      },
    },
    details: {
      memo: 'Test memo',
      recipient: 'alice@example.com',
    },
  };

  beforeEach(async () => {
    const { axiosMock: mock } = await setupTestPinia();
    axiosMock = mock!;
    store = useIncomingStore();
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('Initial State', () => {
    it('has null config on initialization', () => {
      expect(store.config).toBeNull();
    });

    it('has isLoading set to false', () => {
      expect(store.isLoading).toBe(false);
    });

    it('has null configError', () => {
      expect(store.configError).toBeNull();
    });

    it('is not initialized by default', () => {
      expect(store._initialized).toBe(false);
      expect(store.isInitialized).toBe(false);
    });

    it('reports feature as disabled when config is null', () => {
      expect(store.isFeatureEnabled).toBe(false);
    });

    it('returns default memoMaxLength of 50', () => {
      expect(store.memoMaxLength).toBe(50);
    });

    it('returns empty recipients array', () => {
      expect(store.recipients).toEqual([]);
    });

    it('returns undefined defaultTtl', () => {
      expect(store.defaultTtl).toBeUndefined();
    });
  });

  describe('init()', () => {
    it('sets _initialized to true on first call', () => {
      store.init();
      expect(store._initialized).toBe(true);
      expect(store.isInitialized).toBe(true);
    });

    it('returns isInitialized getter on subsequent calls', () => {
      store.init();
      const result = store.init();
      expect(result).toHaveProperty('isInitialized');
    });

    it('ignores api option with warning (logged internally)', () => {
      // This tests that providing api option doesn't throw
      store.init({ api: {} as any });
      expect(store._initialized).toBe(true);
    });
  });

  describe('loadConfig()', () => {
    it('loads and validates config from API', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });

      const result = await store.loadConfig();

      expect(result).toEqual(mockConfig);
      expect(store.config).toEqual(mockConfig);
    });

    it('clears configError before loading', async () => {
      store.configError = 'Previous error';

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });

      await store.loadConfig();

      expect(store.configError).toBeNull();
    });

    it('updates computed getters after loading config', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(true);
      expect(store.memoMaxLength).toBe(100);
      expect(store.recipients).toEqual(mockConfig.recipients);
      expect(store.defaultTtl).toBe(86400);
    });

    it('validates response with Zod schema', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });

      await store.loadConfig();

      // Verify the stored config passes schema validation
      expect(() => incomingConfigSchema.parse(store.config)).not.toThrow();
    });

    it('handles feature disabled config', async () => {
      const disabledConfig = {
        enabled: false,
        memo_max_length: 50,
        recipients: [],
      };

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: disabledConfig,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(false);
      expect(store.recipients).toEqual([]);
    });
  });

  describe('loadConfig() - Error Handling', () => {
    it('throws on network error', async () => {
      axiosMock.onGet('/api/v3/incoming/config').networkError();

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws on 500 server error', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(500, {
        message: 'Internal server error',
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws on 403 forbidden', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(403, {
        message: 'Access denied',
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws on Zod validation failure with invalid data', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: { invalid: 'data' },
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws when recipients have invalid structure', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: {
          enabled: true,
          memo_max_length: 50,
          recipients: [{ invalid_field: 'value' }],
        },
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('preserves previous config state on error', async () => {
      // First load valid config
      axiosMock.onGet('/api/v3/incoming/config').replyOnce(200, {
        config: mockConfig,
      });
      await store.loadConfig();

      const previousConfig = store.config;

      // Second call fails
      axiosMock.onGet('/api/v3/incoming/config').networkError();

      await expect(store.loadConfig()).rejects.toThrow();

      // Config should remain unchanged (store doesn't clear on error)
      expect(store.config).toEqual(previousConfig);
    });
  });

  describe('createIncomingSecret()', () => {
    beforeEach(async () => {
      // Load config first so feature is enabled
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
    });

    it('creates secret with valid payload', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').reply(200, mockSecretResponse);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
        memo: 'Test memo',
      };

      const result = await store.createIncomingSecret(payload);

      expect(result.success).toBe(true);
      expect(result.record).toBeDefined();
      expect(result.record.receipt).toBeDefined();
      expect(result.record.secret).toBeDefined();
    });

    it('sends correct payload structure to API', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').reply(200, mockSecretResponse);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
        memo: 'Test memo',
      };

      await store.createIncomingSecret(payload);

      expect(axiosMock.history.post).toHaveLength(1);
      expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({
        secret: payload,
      });
    });

    it('validates response with Zod schema', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').reply(200, mockSecretResponse);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      const result = await store.createIncomingSecret(payload);

      expect(() => incomingSecretResponseSchema.parse(result)).not.toThrow();
    });

    it('works without optional memo', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').reply(200, mockSecretResponse);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      const result = await store.createIncomingSecret(payload);

      expect(result.success).toBe(true);
    });
  });

  describe('createIncomingSecret() - Feature Disabled', () => {
    it('throws when feature is not enabled', async () => {
      // Config not loaded, so isFeatureEnabled is false
      expect(store.isFeatureEnabled).toBe(false);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow(
        'Incoming secrets feature is not enabled'
      );
    });

    it('throws when config has enabled: false', async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: { enabled: false, memo_max_length: 50, recipients: [] },
      });
      await store.loadConfig();

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow(
        'Incoming secrets feature is not enabled'
      );
    });

    it('does not make API call when feature disabled', async () => {
      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      try {
        await store.createIncomingSecret(payload);
      } catch {
        // Expected to throw
      }

      // No POST request should have been made
      expect(axiosMock.history.post).toHaveLength(0);
    });
  });

  describe('createIncomingSecret() - Error Handling', () => {
    beforeEach(async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
    });

    it('throws on network error', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').networkError();

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on 400 bad request', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').reply(400, {
        message: 'Invalid recipient',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'invalid-hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on Zod validation failure', async () => {
      axiosMock.onPost('/api/v3/incoming/secret').reply(200, {
        invalid: 'response structure',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });
  });

  // Bug #2500: V3 API safe_dump returns null for unset fields
  describe('createIncomingSecret() - Bug #2500: null fields from safe_dump', () => {
    beforeEach(async () => {
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
    });

    it('handles API response with null state fields', async () => {
      const responseWithNulls = {
        ...mockSecretResponse,
        record: {
          receipt: {
            ...mockSecretResponse.record.receipt,
            state: null,
          },
          secret: {
            ...mockSecretResponse.record.secret,
            state: null,
          },
        },
      };
      axiosMock.onPost('/api/v3/incoming/secret').reply(200, responseWithNulls);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      const result = await store.createIncomingSecret(payload);
      expect(result.success).toBe(true);
      expect(result.record.receipt.identifier).toBe('receipt-id-123');
    });

    it('handles API response with null details fields', async () => {
      const responseWithNullDetails = {
        ...mockSecretResponse,
        details: {
          memo: null,
          recipient: null,
        },
      };
      axiosMock
        .onPost('/api/v3/incoming/secret')
        .reply(200, responseWithNullDetails);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      const result = await store.createIncomingSecret(payload);
      expect(result.success).toBe(true);
    });

    it('handles API response with all nullable fields as null', async () => {
      const minimalResponse = {
        success: true,
        message: null,
        shrimp: null,
        custid: null,
        record: {
          receipt: {
            identifier: 'receipt-id-123',
            key: 'receipt-key-123',
            custid: null,
            owner_id: null,
            state: null,
            secret_shortid: null,
            shortid: null,
            memo: null,
            recipients: null,
            secret_ttl: null,
            receipt_ttl: null,
            lifespan: null,
            share_domain: null,
            created: null,
            updated: null,
            shared: null,
            received: null,
            burned: null,
            viewed: null,
            show_recipients: null,
            is_viewed: null,
            is_received: null,
            is_burned: null,
            is_expired: null,
            is_orphaned: null,
            is_destroyed: null,
            has_passphrase: null,
          },
          secret: {
            identifier: 'secret-id-123',
            key: 'secret-key-123',
            state: null,
            shortid: null,
            secret_ttl: null,
            lifespan: null,
            has_passphrase: null,
            verification: null,
            created: null,
            updated: null,
          },
        },
        details: null,
      };
      axiosMock
        .onPost('/api/v3/incoming/secret')
        .reply(200, minimalResponse);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      const result = await store.createIncomingSecret(payload);
      expect(result.success).toBe(true);
      expect(result.record.receipt.identifier).toBe('receipt-id-123');
      expect(result.record.secret.identifier).toBe('secret-id-123');
    });
  });

  describe('clear()', () => {
    beforeEach(async () => {
      // Setup store with data
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
      store.configError = 'Some error';
      store.isLoading = true;
    });

    it('sets config to null', () => {
      store.clear();
      expect(store.config).toBeNull();
    });

    it('sets configError to null', () => {
      store.clear();
      expect(store.configError).toBeNull();
    });

    it('sets isLoading to false', () => {
      store.clear();
      expect(store.isLoading).toBe(false);
    });

    it('does NOT reset _initialized flag', () => {
      store.init();
      store.clear();
      expect(store._initialized).toBe(true);
    });

    it('resets computed getters to defaults', () => {
      store.clear();
      expect(store.isFeatureEnabled).toBe(false);
      expect(store.memoMaxLength).toBe(50);
      expect(store.recipients).toEqual([]);
      expect(store.defaultTtl).toBeUndefined();
    });
  });

  describe('$reset()', () => {
    beforeEach(async () => {
      // Setup store with data
      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
      store.init();
      store.configError = 'Some error';
      store.isLoading = true;
    });

    it('sets config to null', () => {
      store.$reset();
      expect(store.config).toBeNull();
    });

    it('sets configError to null', () => {
      store.$reset();
      expect(store.configError).toBeNull();
    });

    it('sets isLoading to false', () => {
      store.$reset();
      expect(store.isLoading).toBe(false);
    });

    it('resets _initialized to false', () => {
      store.$reset();
      expect(store._initialized).toBe(false);
      expect(store.isInitialized).toBe(false);
    });

    it('resets all computed getters to defaults', () => {
      store.$reset();
      expect(store.isFeatureEnabled).toBe(false);
      expect(store.memoMaxLength).toBe(50);
      expect(store.recipients).toEqual([]);
      expect(store.defaultTtl).toBeUndefined();
    });
  });

  describe('Computed Getters', () => {
    it('isFeatureEnabled reflects config.enabled', async () => {
      expect(store.isFeatureEnabled).toBe(false);

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: { ...mockConfig, enabled: true },
      });
      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(true);
    });

    it('memoMaxLength reflects config.memo_max_length', async () => {
      expect(store.memoMaxLength).toBe(50); // default

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: { ...mockConfig, memo_max_length: 200 },
      });
      await store.loadConfig();

      expect(store.memoMaxLength).toBe(200);
    });

    it('recipients reflects config.recipients', async () => {
      expect(store.recipients).toEqual([]);

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();

      expect(store.recipients).toHaveLength(2);
      expect(store.recipients[0]).toEqual({ hash: 'abc123hash', name: 'Alice' });
    });

    it('defaultTtl reflects config.default_ttl', async () => {
      expect(store.defaultTtl).toBeUndefined();

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: { ...mockConfig, default_ttl: 3600 },
      });
      await store.loadConfig();

      expect(store.defaultTtl).toBe(3600);
    });

    it('defaultTtl remains undefined when not set in config', async () => {
      const configWithoutTtl = {
        enabled: true,
        memo_max_length: 50,
        recipients: [],
      };

      axiosMock.onGet('/api/v3/incoming/config').reply(200, {
        config: configWithoutTtl,
      });
      await store.loadConfig();

      expect(store.defaultTtl).toBeUndefined();
    });
  });

  describe('Schema Validation', () => {
    it('accepts valid config with all fields', () => {
      const result = incomingConfigSchema.parse(mockConfig);
      expect(result.enabled).toBe(true);
      expect(result.memo_max_length).toBe(100);
      expect(result.recipients).toHaveLength(2);
      expect(result.default_ttl).toBe(86400);
    });

    it('applies default memo_max_length of 50', () => {
      const result = incomingConfigSchema.parse({
        enabled: true,
        recipients: [],
      });
      expect(result.memo_max_length).toBe(50);
    });

    it('applies default empty recipients array', () => {
      const result = incomingConfigSchema.parse({
        enabled: true,
        memo_max_length: 50,
      });
      expect(result.recipients).toEqual([]);
    });

    it('rejects config with missing enabled field', () => {
      expect(() =>
        incomingConfigSchema.parse({
          memo_max_length: 50,
          recipients: [],
        })
      ).toThrow();
    });

    it('rejects recipient with missing hash', () => {
      expect(() =>
        incomingConfigSchema.parse({
          enabled: true,
          memo_max_length: 50,
          recipients: [{ name: 'Alice' }],
        })
      ).toThrow();
    });

    it('rejects recipient with empty hash', () => {
      expect(() =>
        incomingConfigSchema.parse({
          enabled: true,
          memo_max_length: 50,
          recipients: [{ hash: '', name: 'Alice' }],
        })
      ).toThrow();
    });
  });
});
