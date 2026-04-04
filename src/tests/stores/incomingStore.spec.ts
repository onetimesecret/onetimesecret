// src/tests/stores/incomingStore.spec.ts

import {
  incomingConfigSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';
import { useIncomingStore } from '@/shared/stores/incomingStore';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { setupTestPinia } from '../setup';
import {
  mockReceiptRecordRaw,
  mockReceiptDetailsRaw,
} from '../fixtures/receipt.fixture';

describe('incomingStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useIncomingStore>;

  // Valid mock config matching incomingConfigSchema
  const mockConfig = {
    enabled: true,
    memo_max_length: 100,
    recipients: [
      { digest: 'abc123hash', display_name: 'Alice' },
      { digest: 'def456hash', display_name: 'Bob' },
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

    it('has null entitlementError', () => {
      expect(store.entitlementError).toBeNull();
    });

    it('is not initialized by default', () => {
      expect(store._initialized).toBe(false);
      expect(store.isInitialized).toBe(false);
    });

    it('reports feature as disabled when config is null', () => {
      expect(store.isFeatureEnabled).toBe(false);
    });

    it('reports entitlement as not blocked', () => {
      expect(store.isEntitlementBlocked).toBe(false);
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
      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: mockConfig,
      });

      const result = await store.loadConfig();

      expect(result).toEqual(mockConfig);
      expect(store.config).toEqual(mockConfig);
    });

    it('clears configError before loading', async () => {
      store.configError = 'Previous error';

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: mockConfig,
      });

      await store.loadConfig();

      expect(store.configError).toBeNull();
    });

    it('updates computed getters after loading config', async () => {
      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: mockConfig,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(true);
      expect(store.memoMaxLength).toBe(100);
      expect(store.recipients).toEqual(mockConfig.recipients);
      expect(store.defaultTtl).toBe(86400);
    });

    it('validates response with Zod schema', async () => {
      axiosMock.onGet('/api/incoming/config').reply(200, {
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

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: disabledConfig,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(false);
      expect(store.recipients).toEqual([]);
    });
  });

  describe('loadConfig() - Error Handling', () => {
    it('throws on network error', async () => {
      axiosMock.onGet('/api/incoming/config').networkError();

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws on 500 server error', async () => {
      axiosMock.onGet('/api/incoming/config').reply(500, {
        message: 'Internal server error',
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws on 403 forbidden', async () => {
      axiosMock.onGet('/api/incoming/config').reply(403, {
        message: 'Access denied',
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws on Zod validation failure with invalid data', async () => {
      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: { invalid: 'data' },
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('throws when recipients have invalid structure', async () => {
      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: {
          enabled: true,
          memo_max_length: 50,
          recipients: [{ invalid_field: 'value' }],
        },
      });

      await expect(store.loadConfig()).rejects.toThrow();
    });

    it('captures entitlement 403 without throwing', async () => {
      axiosMock.onGet('/api/incoming/config').reply(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
      });

      const result = await store.loadConfig();

      expect(result).toBeUndefined();
      expect(store.entitlementError).toEqual({
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
      });
      expect(store.isEntitlementBlocked).toBe(true);
    });

    it('parses full entitlement 403 payload with plan info', async () => {
      axiosMock.onGet('/api/incoming/config').reply(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
        current_plan: 'free_v1',
        upgrade_to: 'identity_plus_v1',
      });

      await store.loadConfig();

      expect(store.entitlementError).toEqual({
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
        current_plan: 'free_v1',
        upgrade_to: 'identity_plus_v1',
      });
    });

    it('still throws non-entitlement 403 errors', async () => {
      axiosMock.onGet('/api/incoming/config').reply(403, {
        message: 'Access denied',
      });

      await expect(store.loadConfig()).rejects.toThrow();
      expect(store.entitlementError).toBeNull();
      expect(store.isEntitlementBlocked).toBe(false);
    });

    it('handles malformed 403 entitlement payload gracefully', async () => {
      // Payload has entitlement field (so it's detected as entitlement error)
      // but is missing required 'error' field, making it fail schema validation
      axiosMock.onGet('/api/incoming/config').reply(403, {
        entitlement: 'incoming_secrets',
        // missing 'error' field required by entitlementErrorSchema
        some_extra_field: 'unexpected',
      });

      const result = await store.loadConfig();

      // Should not throw, instead use fallback entitlementError
      expect(result).toBeUndefined();
      expect(store.entitlementError).toEqual({
        entitlement: 'incoming_secrets',
      });
      expect(store.isEntitlementBlocked).toBe(true);
    });

    it('clears entitlementError on subsequent successful load', async () => {
      // First: entitlement error
      axiosMock.onGet('/api/incoming/config').replyOnce(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
      });
      await store.loadConfig();
      expect(store.isEntitlementBlocked).toBe(true);

      // Second: success
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: mockConfig,
      });
      await store.loadConfig();

      expect(store.entitlementError).toBeNull();
      expect(store.isEntitlementBlocked).toBe(false);
      expect(store.config).toEqual(mockConfig);
    });

    it('preserves previous config state on error', async () => {
      // First load valid config
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: mockConfig,
      });
      await store.loadConfig();

      const previousConfig = store.config;

      // Second call fails
      axiosMock.onGet('/api/incoming/config').networkError();

      await expect(store.loadConfig()).rejects.toThrow();

      // Config should remain unchanged (store doesn't clear on error)
      expect(store.config).toEqual(previousConfig);
    });

    it('leaves config null and isFeatureEnabled false after network error', async () => {
      // Network error - config stays null, feature disabled
      axiosMock.onGet('/api/incoming/config').networkError();

      await expect(store.loadConfig()).rejects.toThrow();

      expect(store.config).toBeNull();
      expect(store.isFeatureEnabled).toBe(false);
    });
  });

  describe('createIncomingSecret()', () => {
    beforeEach(async () => {
      // Load config first so feature is enabled
      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
    });

    it('creates secret with valid payload', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(200, mockSecretResponse);

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
      axiosMock.onPost('/api/incoming/secret').reply(200, mockSecretResponse);

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
      axiosMock.onPost('/api/incoming/secret').reply(200, mockSecretResponse);

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      const result = await store.createIncomingSecret(payload);

      expect(() => incomingSecretResponseSchema.parse(result)).not.toThrow();
    });

    it('works without optional memo', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(200, mockSecretResponse);

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
      axiosMock.onGet('/api/incoming/config').reply(200, {
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
      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();
    });

    it('throws on network error', async () => {
      axiosMock.onPost('/api/incoming/secret').networkError();

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on 400 bad request', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(400, {
        message: 'Invalid recipient',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'invalid-hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on Zod validation failure', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(200, {
        invalid: 'response structure',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on 403 entitlement error from POST endpoint', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      // Unlike loadConfig, createIncomingSecret does not capture entitlement errors
      // It throws on all 403 responses since the pre-flight config check should catch this
      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on 403 with plan upgrade info from POST endpoint', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
        current_plan: 'free_v1',
        upgrade_to: 'identity_plus_v1',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('throws on 403 non-entitlement error from POST endpoint', async () => {
      axiosMock.onPost('/api/incoming/secret').reply(403, {
        message: 'Access denied - invalid session',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();
    });

    it('does not set entitlementError on POST 403 (only loadConfig captures it)', async () => {
      // POST endpoint throws on all 403s - entitlement gating should be caught
      // by the pre-flight loadConfig call, not the POST. This verifies the
      // architectural expectation that createIncomingSecret does not capture
      // entitlement errors into store state.
      axiosMock.onPost('/api/incoming/secret').reply(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
      });

      const payload = {
        secret: 'my secret value',
        recipient: 'abc123hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow();

      // entitlementError should remain null - POST path doesn't set it
      expect(store.entitlementError).toBeNull();
      expect(store.isEntitlementBlocked).toBe(false);
    });
  });

  describe('clear()', () => {
    beforeEach(async () => {
      // Setup store with data
      axiosMock.onGet('/api/incoming/config').reply(200, {
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

    it('sets entitlementError to null', () => {
      store.entitlementError = {
        error: 'test',
        entitlement: 'incoming_secrets',
      };
      store.clear();
      expect(store.entitlementError).toBeNull();
      expect(store.isEntitlementBlocked).toBe(false);
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
      axiosMock.onGet('/api/incoming/config').reply(200, {
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

    it('sets entitlementError to null', () => {
      store.entitlementError = {
        error: 'test',
        entitlement: 'incoming_secrets',
      };
      store.$reset();
      expect(store.entitlementError).toBeNull();
      expect(store.isEntitlementBlocked).toBe(false);
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

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: { ...mockConfig, enabled: true },
      });
      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(true);
    });

    it('memoMaxLength reflects config.memo_max_length', async () => {
      expect(store.memoMaxLength).toBe(50); // default

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: { ...mockConfig, memo_max_length: 200 },
      });
      await store.loadConfig();

      expect(store.memoMaxLength).toBe(200);
    });

    it('recipients reflects config.recipients', async () => {
      expect(store.recipients).toEqual([]);

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: mockConfig,
      });
      await store.loadConfig();

      expect(store.recipients).toHaveLength(2);
      expect(store.recipients[0]).toEqual({ digest: 'abc123hash', display_name: 'Alice' });
    });

    it('defaultTtl reflects config.default_ttl', async () => {
      expect(store.defaultTtl).toBeUndefined();

      axiosMock.onGet('/api/incoming/config').reply(200, {
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

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: configWithoutTtl,
      });
      await store.loadConfig();

      expect(store.defaultTtl).toBeUndefined();
    });
  });

  describe('Config Response Variations', () => {
    // These tests verify the store correctly handles different config shapes
    // returned by the backend. Domain routing (canonical vs custom) is handled
    // server-side based on the request's Host header. The store receives the
    // resolved config and exposes it via getters for UI consumption.
    //
    // Note: createIncomingSecret does not inject config values (TTL, memo limit)
    // into the request - it only gates on `enabled`. The server applies domain-
    // specific limits when processing the secret.

    it('handles config with global recipients', async () => {
      const config = {
        enabled: true,
        memo_max_length: 100,
        recipients: [
          { digest: 'global-hash-1', display_name: 'Global Recipient 1' },
          { digest: 'global-hash-2', display_name: 'Global Recipient 2' },
        ],
        default_ttl: 86400,
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(true);
      expect(store.recipients).toHaveLength(2);
      expect(store.recipients[0].digest).toBe('global-hash-1');
    });

    it('handles config with multiple recipients and extended TTL', async () => {
      const config = {
        enabled: true,
        memo_max_length: 200,
        recipients: [
          { digest: 'acme-hash-1', display_name: 'ACME Support' },
          { digest: 'acme-hash-2', display_name: 'ACME Security' },
          { digest: 'acme-hash-3', display_name: 'ACME HR' },
        ],
        default_ttl: 172800,
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(true);
      expect(store.recipients).toHaveLength(3);
      expect(store.memoMaxLength).toBe(200);
      expect(store.defaultTtl).toBe(172800);
    });

    it('handles disabled config with empty recipients', async () => {
      const config = {
        enabled: false,
        memo_max_length: 50,
        recipients: [],
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config,
      });

      await store.loadConfig();

      expect(store.isFeatureEnabled).toBe(false);
      expect(store.recipients).toEqual([]);
    });

    it('handles config with elevated memo limit and extended TTL', async () => {
      const config = {
        enabled: true,
        memo_max_length: 500,
        recipients: [{ digest: 'enterprise-hash', display_name: 'Enterprise Team' }],
        default_ttl: 604800, // 7 days
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config,
      });

      await store.loadConfig();

      expect(store.memoMaxLength).toBe(500);
      expect(store.defaultTtl).toBe(604800);
    });

    it('createIncomingSecret succeeds after loading domain-specific config', async () => {
      // Load config with custom domain-like settings
      const domainConfig = {
        enabled: true,
        memo_max_length: 300,
        recipients: [
          { digest: 'domain-recipient-1', display_name: 'Domain Support' },
        ],
        default_ttl: 259200, // 3 days
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: domainConfig,
      });
      await store.loadConfig();

      // Verify store reflects loaded config
      expect(store.memoMaxLength).toBe(300);
      expect(store.defaultTtl).toBe(259200);

      // Now create a secret - the store gates on enabled but doesn't inject TTL/memo
      axiosMock.onPost('/api/incoming/secret').reply(200, mockSecretResponse);

      const payload = {
        secret: 'domain secret value',
        recipient: 'domain-recipient-1',
        memo: 'Test for domain context',
      };

      const result = await store.createIncomingSecret(payload);

      expect(result.success).toBe(true);
      // Verify the request was made (server applies domain config server-side)
      expect(axiosMock.history.post).toHaveLength(1);
    });
  });

  describe('Resolver Enabled Fallback Behavior', () => {
    // Tests for when entitlement passes but resolver.enabled is false in the config response
    // The config response includes enabled: boolean which reflects resolver.enabled? on backend

    it('reports feature disabled when config.enabled is false despite valid recipients', async () => {
      // Edge case: config has recipients but enabled is false
      // This can happen when a custom domain has recipients but incoming is globally disabled
      const configWithDisabledFeature = {
        enabled: false,
        memo_max_length: 100,
        recipients: [
          { digest: 'orphan-hash-1', display_name: 'Orphan Recipient' },
        ],
        default_ttl: 86400,
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: configWithDisabledFeature,
      });

      await store.loadConfig();

      expect(store.config).not.toBeNull();
      expect(store.config?.enabled).toBe(false);
      expect(store.isFeatureEnabled).toBe(false);
      // Recipients are present but feature is disabled
      expect(store.recipients).toHaveLength(1);
    });

    it('blocks secret creation when config.enabled is false', async () => {
      const disabledConfig = {
        enabled: false,
        memo_max_length: 50,
        recipients: [{ digest: 'test-hash', display_name: 'Test' }],
      };

      axiosMock.onGet('/api/incoming/config').reply(200, {
        config: disabledConfig,
      });
      await store.loadConfig();

      const payload = {
        secret: 'my secret value',
        recipient: 'test-hash',
      };

      await expect(store.createIncomingSecret(payload)).rejects.toThrow(
        'Incoming secrets feature is not enabled'
      );
    });

    it('correctly transitions from disabled to enabled on config reload', async () => {
      // First load: disabled
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: {
          enabled: false,
          memo_max_length: 50,
          recipients: [],
        },
      });

      await store.loadConfig();
      expect(store.isFeatureEnabled).toBe(false);

      // Second load: enabled (admin configured the domain)
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: {
          enabled: true,
          memo_max_length: 100,
          recipients: [{ digest: 'new-hash', display_name: 'New Recipient' }],
        },
      });

      await store.loadConfig();
      expect(store.isFeatureEnabled).toBe(true);
      expect(store.recipients).toHaveLength(1);
    });

    it('correctly transitions from enabled to disabled on config reload', async () => {
      // First load: enabled
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: mockConfig, // enabled: true
      });

      await store.loadConfig();
      expect(store.isFeatureEnabled).toBe(true);

      // Second load: disabled (admin removed recipients or disabled feature)
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: {
          enabled: false,
          memo_max_length: 50,
          recipients: [],
        },
      });

      await store.loadConfig();
      expect(store.isFeatureEnabled).toBe(false);
    });

    it('distinguishes between entitlement blocked and feature disabled states', async () => {
      // Test that isEntitlementBlocked and isFeatureEnabled are independent

      // Entitlement blocked state
      axiosMock.onGet('/api/incoming/config').replyOnce(403, {
        error: 'Feature requires incoming secrets entitlement',
        entitlement: 'incoming_secrets',
      });

      await store.loadConfig();

      expect(store.isEntitlementBlocked).toBe(true);
      expect(store.isFeatureEnabled).toBe(false);
      expect(store.config).toBeNull();

      // Reset and test feature disabled state (different from entitlement blocked)
      store.$reset();
      axiosMock.onGet('/api/incoming/config').replyOnce(200, {
        config: {
          enabled: false,
          memo_max_length: 50,
          recipients: [],
        },
      });

      await store.loadConfig();

      expect(store.isEntitlementBlocked).toBe(false);
      expect(store.isFeatureEnabled).toBe(false);
      expect(store.config).not.toBeNull();
    });
  });

  describe('getReceipt()', () => {
    const receiptKey = 'testkey123';
    const mockReceiptApiResponse = {
      record: mockReceiptRecordRaw,
      details: mockReceiptDetailsRaw,
    };

    it('fetches receipt data for a valid key', async () => {
      axiosMock
        .onGet(`/api/v3/guest/receipt/${receiptKey}`)
        .reply(200, mockReceiptApiResponse);

      const result = await store.getReceipt(receiptKey);

      expect(result).toBeDefined();
      expect(result.record).toBeDefined();
      expect(result.record.identifier).toBe(mockReceiptRecordRaw.identifier);
    });

    it('calls the correct API endpoint with the key', async () => {
      axiosMock
        .onGet(`/api/v3/guest/receipt/${receiptKey}`)
        .reply(200, mockReceiptApiResponse);

      await store.getReceipt(receiptKey);

      expect(axiosMock.history.get).toHaveLength(1);
      expect(axiosMock.history.get[0].url).toBe(
        `/api/v3/guest/receipt/${receiptKey}`
      );
    });

    it('throws on 404 server error', async () => {
      axiosMock
        .onGet(`/api/v3/guest/receipt/${receiptKey}`)
        .reply(404, { message: 'Receipt not found' });

      await expect(store.getReceipt(receiptKey)).rejects.toThrow();
    });

    it('throws on network error', async () => {
      axiosMock
        .onGet(`/api/v3/guest/receipt/${receiptKey}`)
        .networkError();

      await expect(store.getReceipt(receiptKey)).rejects.toThrow();
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

    it('rejects recipient with missing digest', () => {
      expect(() =>
        incomingConfigSchema.parse({
          enabled: true,
          memo_max_length: 50,
          recipients: [{ display_name: 'Alice' }],
        })
      ).toThrow();
    });

    it('rejects recipient with empty digest', () => {
      expect(() =>
        incomingConfigSchema.parse({
          enabled: true,
          memo_max_length: 50,
          recipients: [{ digest: '', display_name: 'Alice' }],
        })
      ).toThrow();
    });
  });
});
