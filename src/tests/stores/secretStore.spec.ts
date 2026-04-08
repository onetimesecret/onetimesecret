// src/tests/stores/secretStore.spec.ts

import { useSecretStore } from '@/shared/stores/secretStore';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App, ComponentPublicInstance } from 'vue';

import { AxiosInstance } from 'axios';
import {
  mockSecretRecord,
  mockSecretRecordRaw,
  mockSecretResponse,
} from '../fixtures/receipt.fixture';
import { setupTestPinia } from '../setup';
import { setupBootstrapMock } from '../setup-bootstrap';
import { baseBootstrap } from '@/tests/fixtures/bootstrap.fixture';

describe('secretStore', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let _app: App<Element>;
  let _appInstance: ComponentPublicInstance | null;
  let store: ReturnType<typeof useSecretStore>;

  beforeEach(async () => {
    // Use the utility function
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    _appInstance = setup.appInstance;

    // Create mock adapter
    axiosMock = new AxiosMockAdapter(api);

    // Setup bootstrap state with modern fixture (shrimp defaults to 'test-csrf-token')
    setupBootstrapMock({ initialState: { ...baseBootstrap, shrimp: '' } });

    // Initialize store
    store = useSecretStore();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.useRealTimers();
    vi.unstubAllGlobals();
    if (axiosMock) axiosMock.reset();
  });

  describe('Initialization', () => {
    it('initializes correctly', () => {
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
    });
  });

  describe('apiMode', () => {
    it('defaults to authenticated mode', () => {
      expect(store.apiMode).toBe('authenticated');
    });

    it('can be changed to public mode', () => {
      store.setApiMode('public');
      expect(store.apiMode).toBe('public');
    });

    it('can be changed back to authenticated mode', () => {
      store.setApiMode('public');
      store.setApiMode('authenticated');
      expect(store.apiMode).toBe('authenticated');
    });

    it('$reset resets apiMode to authenticated', () => {
      store.setApiMode('public');
      store.$reset();
      expect(store.apiMode).toBe('authenticated');
    });

    it('persists apiMode across multiple operations', async () => {
      store.setApiMode('public');

      // Mock responses for public endpoints
      axiosMock?.onGet('/api/v3/guest/secret/abc123').reply(200, mockSecretResponse);
      axiosMock?.onPost('/api/v3/guest/secret/abc123/reveal').reply(200, {
        ...mockSecretResponse,
        record: { ...mockSecretRecordRaw, secret_value: 'revealed' },
        details: { ...mockSecretResponse.details, show_secret: true },
      });

      // Perform multiple operations
      await store.fetch('abc123');
      await store.reveal('abc123', 'password');

      // Both should have used public endpoints
      expect(axiosMock?.history.get[0].url).toBe('/api/v3/guest/secret/abc123');
      expect(axiosMock?.history.post[0].url).toBe('/api/v3/guest/secret/abc123/reveal');
    });

    it('clear() does not affect apiMode', () => {
      store.setApiMode('public');
      store.clear();
      expect(store.apiMode).toBe('public');
    });

    describe('endpoint selection', () => {
      const mockConcealResponse = {
        record: {
          receipt: { key: 'receipt-key', identifier: 'receipt-id' },
          secret: { key: 'secret-key', identifier: 'secret-id' },
        },
        details: { uri: '/secret/secret-id' },
      };

      it('conceal() uses /api/v3/secret/conceal in authenticated mode', async () => {
        axiosMock?.onPost('/api/v3/secret/conceal').reply(200, mockConcealResponse);

        await store.conceal({ secret: 'test', ttl: 3600, kind: 'conceal' });

        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/secret/conceal');
      });

      it('conceal() uses /api/v3/guest/secret/conceal in public mode', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/conceal').reply(200, mockConcealResponse);

        await store.conceal({ secret: 'test', ttl: 3600, kind: 'conceal' });

        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/guest/secret/conceal');
      });

      it('generate() uses /api/v3/secret/generate in authenticated mode', async () => {
        axiosMock?.onPost('/api/v3/secret/generate').reply(200, mockConcealResponse);

        await store.generate({ ttl: 3600, kind: 'generate' });

        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/secret/generate');
      });

      it('generate() uses /api/v3/guest/secret/generate in public mode', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/generate').reply(200, mockConcealResponse);

        await store.generate({ ttl: 3600, kind: 'generate' });

        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/guest/secret/generate');
      });

      it('fetch() uses /api/v3/secret/:id in authenticated mode', async () => {
        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

        await store.fetch('abc123');

        expect(axiosMock?.history.get.length).toBe(1);
        expect(axiosMock?.history.get[0].url).toBe('/api/v3/secret/abc123');
      });

      it('fetch() uses /api/v3/guest/secret/:id in public mode', async () => {
        store.setApiMode('public');
        axiosMock?.onGet('/api/v3/guest/secret/abc123').reply(200, mockSecretResponse);

        await store.fetch('abc123');

        expect(axiosMock?.history.get.length).toBe(1);
        expect(axiosMock?.history.get[0].url).toBe('/api/v3/guest/secret/abc123');
      });

      it('reveal() uses /api/v3/secret/:id/reveal in authenticated mode', async () => {
        axiosMock?.onPost('/api/v3/secret/abc123/reveal').reply(200, {
          ...mockSecretResponse,
          record: { ...mockSecretRecordRaw, secret_value: 'revealed' },
          details: { ...mockSecretResponse.details, show_secret: true },
        });

        await store.reveal('abc123', 'password');

        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/secret/abc123/reveal');
      });

      it('reveal() uses /api/v3/guest/secret/:id/reveal in public mode', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/abc123/reveal').reply(200, {
          ...mockSecretResponse,
          record: { ...mockSecretRecordRaw, secret_value: 'revealed' },
          details: { ...mockSecretResponse.details, show_secret: true },
        });

        await store.reveal('abc123', 'password');

        expect(axiosMock?.history.post.length).toBe(1);
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/guest/secret/abc123/reveal');
      });
    });
  });

  describe('fetch', () => {
    it('debug response transformation', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      // After parse, timestamps are Dates — compare against transformed fixture
      expect(store.record).toEqual(mockSecretRecord);
      expect(store.details).toEqual(mockSecretResponse.details);

      // Test individual fields
      expect(store.record?.lifespan).toBe(mockSecretRecord.lifespan);
    });

    it('loads secret details successfully (everything except lifespan)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      const { lifespan: _, ...recordWithoutLifespan } = store.record!;
      const { lifespan: __, ...expectedWithoutLifespan } = mockSecretRecord;

      expect(recordWithoutLifespan).toEqual(expectedWithoutLifespan);
      expect(typeof store.record?.lifespan).toBe('number');
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    it('loads secret details successfully (original)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      expect(store.record).toEqual(mockSecretRecord);
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    it('loads secret details successfully (strict values)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      expect(store.record).toEqual(mockSecretRecord);
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    it('loads secret details successfully (looser values)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      const { lifespan: _, ...recordWithoutLifespan } = store.record!;
      const { lifespan: __, ...expectedWithoutLifespan } = mockSecretRecord;

      expect(recordWithoutLifespan).toEqual(expectedWithoutLifespan);
      expect(typeof store.record?.lifespan).toBe('number');
      expect(store.record?.lifespan).toBeGreaterThan(0);
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    it('handles validation errors', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, { invalid: 'data' });

      await expect(store.fetch('abc123')).rejects.toThrow();
      // add: expect error to be raised
    });

    it('handles network errors', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').networkError();

      await expect(store.fetch('abc123')).rejects.toThrow();
    });

    it('loads secret details successfully', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      expect(store.record).toEqual(mockSecretRecord);
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    // For error tests, focus on store state integrity
    it('preserves state on error', async () => {
      // Setup initial state
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);
      await store.fetch('abc123');
      const initialState = { record: store.record, details: store.details };

      // Force error on reveal
      axiosMock?.onPost('/api/v3/secret/abc123/reveal').networkError();

      await expect(store.reveal('abc123', 'wrong')).rejects.toThrow();

      // Verify store state integrity
      expect(store.record).toEqual(initialState.record);
      expect(store.details).toEqual(initialState.details);
    });
  });

  describe('reveal', () => {
    it('reveals secret with passphrase', async () => {
      axiosMock?.onPost('/api/v3/secret/abc123/reveal').reply(200, {
        success: true,
        record: {
          ...mockSecretRecordRaw,
          secret_value: 'revealed secret',
        },
        details: {
          continue: false,
          show_secret: true,
          correct_passphrase: true,
          display_lines: 1,
          one_liner: true,
          is_owner: false, // Add required field
        },
      });

      await store.reveal('abc123', 'password');

      expect(store.record?.secret_value).toBe('revealed secret');
      expect(store.details?.show_secret).toBe(true);
    });

    it('preserves state on error', async () => {
      // Setup initial state
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);
      await store.fetch('abc123');
      const initialState = { record: store.record, details: store.details };

      // Force error on reveal
      axiosMock?.onPost('/api/v3/secret/abc123/reveal').networkError();

      await expect(store.reveal('abc123', 'wrong')).rejects.toThrow();
      expect(store.record).toEqual(initialState.record);
      expect(store.details).toEqual(initialState.details);
    });
  });

  describe('clearSecret', () => {
    it('resets store state', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');
      store.clear();

      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
      // add: expect error to be null
    });
  });

  describe('field handling', () => {
    describe('is_owner field', () => {
      it('handles is_owner true from API', async () => {
        const ownerResponse = {
          ...mockSecretResponse,
          details: {
            ...mockSecretResponse.details,
            is_owner: true,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, ownerResponse);
        await store.fetch('abc123');

        expect(store.details?.is_owner).toBe(true);
      });

      it('handles is_owner false from API', async () => {
        const nonOwnerResponse = {
          ...mockSecretResponse,
          details: {
            ...mockSecretResponse.details,
            is_owner: false,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, nonOwnerResponse);
        await store.fetch('abc123');

        expect(store.details?.is_owner).toBe(false);
      });

      it('rejects missing is_owner field from API (V3 requires boolean)', async () => {
        const responseWithoutOwner = {
          ...mockSecretResponse,
          details: {
            ...mockSecretResponse.details,
            is_owner: undefined,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, responseWithoutOwner);

        // V3 schema requires z.boolean() — undefined is rejected
        await expect(store.fetch('abc123')).rejects.toThrow();
      });
    });

    describe('lifespan field', () => {
      it('passes through numeric TTL values', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            secret_ttl: 86400,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, response);
        await store.fetch('abc123');

        expect(store.record?.lifespan).toBeDefined();
        expect(typeof store.record?.lifespan).toBe('number');
        expect(store.record?.lifespan).toBe(86400);
      });

      it('rejects null TTL values (V3 requires numbers)', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            secret_ttl: null,
            lifespan: null,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, response);

        // V3 schema requires z.number() — null is rejected
        await expect(store.fetch('abc123')).rejects.toThrow();
      });

      it('handles zero lifespan from API', async () => {
        const zeroLifespanResponse = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: 0,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, zeroLifespanResponse);
        await store.fetch('abc123');

        expect(typeof store.record?.lifespan).toBe('number');
        expect(store.record?.lifespan).toBe(0);
      });

      it('rejects null lifespan from API (V3 requires numbers)', async () => {
        const nullLifespanResponse = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: null,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, nullLifespanResponse);

        await expect(store.fetch('abc123')).rejects.toThrow();
      });

      it('rejects missing lifespan field from API (V3 requires numbers)', async () => {
        const responseWithoutLifespan = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: undefined,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, responseWithoutLifespan);

        // V3 schema requires z.number() — undefined is rejected
        await expect(store.fetch('abc123')).rejects.toThrow();
      });
    });
  });

  describe('guest routes error handling', () => {
    // These tests verify that guest routes 403 errors bubble up correctly
    // from the store. Per project architecture, stores bubble errors and
    // composables/components handle them with useAsyncHandler.wrap()

    describe('GUEST_ROUTES_DISABLED errors', () => {
      const guestRoutesDisabledResponse = {
        message: 'Guest API access is disabled',
        code: 'GUEST_ROUTES_DISABLED',
      };

      it('conceal() rejects with 403 when guest routes globally disabled', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/conceal').reply(403, guestRoutesDisabledResponse);

        await expect(
          store.conceal({ secret: 'test', ttl: 3600, kind: 'conceal' })
        ).rejects.toThrow();
      });

      it('generate() rejects with 403 when guest routes globally disabled', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/generate').reply(403, guestRoutesDisabledResponse);

        await expect(store.generate({ ttl: 3600, kind: 'generate' })).rejects.toThrow();
      });

      it('fetch() rejects with 403 when guest routes globally disabled', async () => {
        store.setApiMode('public');
        axiosMock?.onGet('/api/v3/guest/secret/abc123').reply(403, guestRoutesDisabledResponse);

        await expect(store.fetch('abc123')).rejects.toThrow();
      });

      it('reveal() rejects with 403 when guest routes globally disabled', async () => {
        store.setApiMode('public');
        axiosMock
          ?.onPost('/api/v3/guest/secret/abc123/reveal')
          .reply(403, guestRoutesDisabledResponse);

        await expect(store.reveal('abc123', 'password')).rejects.toThrow();
      });

      it('store state remains unchanged after 403 error', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/conceal').reply(403, guestRoutesDisabledResponse);

        const initialRecord = store.record;
        const initialDetails = store.details;

        await expect(
          store.conceal({ secret: 'test', ttl: 3600, kind: 'conceal' })
        ).rejects.toThrow();

        expect(store.record).toBe(initialRecord);
        expect(store.details).toBe(initialDetails);
      });
    });

    describe('operation-specific disabled errors', () => {
      it('conceal() rejects with GUEST_CONCEAL_DISABLED code', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/conceal').reply(403, {
          message: 'Guest conceal is disabled',
          code: 'GUEST_CONCEAL_DISABLED',
        });

        await expect(
          store.conceal({ secret: 'test', ttl: 3600, kind: 'conceal' })
        ).rejects.toThrow();
      });

      it('generate() rejects with GUEST_GENERATE_DISABLED code', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/generate').reply(403, {
          message: 'Guest generate is disabled',
          code: 'GUEST_GENERATE_DISABLED',
        });

        await expect(store.generate({ ttl: 3600, kind: 'generate' })).rejects.toThrow();
      });

      it('reveal() rejects with GUEST_REVEAL_DISABLED code', async () => {
        store.setApiMode('public');
        axiosMock?.onPost('/api/v3/guest/secret/abc123/reveal').reply(403, {
          message: 'Guest reveal is disabled',
          code: 'GUEST_REVEAL_DISABLED',
        });

        await expect(store.reveal('abc123', 'password')).rejects.toThrow();
      });

      it('fetch() rejects with GUEST_SHOW_DISABLED code', async () => {
        store.setApiMode('public');
        axiosMock?.onGet('/api/v3/guest/secret/abc123').reply(403, {
          message: 'Guest show is disabled',
          code: 'GUEST_SHOW_DISABLED',
        });

        await expect(store.fetch('abc123')).rejects.toThrow();
      });
    });

    describe('authenticated mode unaffected by guest route errors', () => {
      it('conceal() succeeds in authenticated mode regardless of guest config', async () => {
        // Authenticated mode should not be affected by guest route config
        store.setApiMode('authenticated');

        const mockConcealResponse = {
          record: {
            receipt: { key: 'receipt-key', identifier: 'receipt-id' },
            secret: { key: 'secret-key', identifier: 'secret-id' },
          },
          details: { uri: '/secret/secret-id' },
        };

        axiosMock?.onPost('/api/v3/secret/conceal').reply(200, mockConcealResponse);

        const result = await store.conceal({ secret: 'test', ttl: 3600, kind: 'conceal' });

        expect(result).toBeDefined();
        expect(axiosMock?.history.post[0].url).toBe('/api/v3/secret/conceal');
      });
    });
  });
});
