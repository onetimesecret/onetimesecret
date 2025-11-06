// src/tests/stores/secretStore.spec.ts

import { useSecretStore } from '@/stores/secretStore';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { App, ComponentPublicInstance } from 'vue';

import { AxiosInstance } from 'axios';
import { mockSecretRecord, mockSecretResponse } from '../fixtures/metadata.fixture';
import { setupTestPinia } from '../setup';
import { setupWindowState } from '../setupWindow';

describe('secretStore', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let app: App<Element>;
  let appInstance: ComponentPublicInstance | null;
  let store: ReturnType<typeof useSecretStore>;

  beforeEach(async () => {
    // Use the utility function
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    appInstance = setup.appInstance;

    // Create mock adapter
    axiosMock = new AxiosMockAdapter(api);

    const windowMock = setupWindowState({ shrimp: undefined });
    vi.stubGlobal('window', windowMock);

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

  describe('fetch', () => {
    it('debug response transformation', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      // // Log the mock response
      // console.log('Mock Response:', JSON.stringify(mockSecretResponse, null, 2));

      await store.fetch('abc123');

      // // Log what's in the store
      // console.log('Store Record:', JSON.stringify(store.record, null, 2));

      expect(store.record).toEqual(mockSecretResponse.record);
      expect(store.details).toEqual(mockSecretResponse.details);

      // Test individual fields
      expect(store.record?.lifespan).toBe(mockSecretResponse.record.lifespan);
      // Other fields...
    });

    it('loads secret details successfully (everything except lifespan)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      // Test everything except lifespan
      const { lifespan: _, ...recordWithoutLifespan } = store.record!;
      const { lifespan: __, ...expectedWithoutLifespan } = mockSecretResponse.record;

      expect(recordWithoutLifespan).toEqual(expectedWithoutLifespan);
      // Test that lifespan exists and is a number (transformed by schema)
      expect(typeof store.record?.lifespan).toBe('number');
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    it('loads secret details successfully (original)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      expect(store.record).toEqual(mockSecretResponse.record);
      expect(store.details).toEqual(mockSecretResponse.details);
      // add: expect error to be null
    });

    // Test the transformed values exactly (more brittle but more precise)
    it('loads secret details successfully (strict values)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      const expectedRecord = {
        ...mockSecretResponse.record,
        lifespan: 86400, // Schema transforms to number
      };

      expect(store.record).toEqual(expectedRecord);
      expect(store.details).toEqual(mockSecretResponse.details);
    });

    // Test for shape and types rather than exact values for transformed fields
    it('loads secret details successfully (looser values)', async () => {
      axiosMock?.onGet('/api/v3/secret/abc123').reply(200, mockSecretResponse);

      await store.fetch('abc123');

      // Check record shape and transformed fields separately
      const { lifespan: _, ...recordWithoutLifespan } = store.record!;
      const { lifespan: __, ...expectedWithoutLifespan } = mockSecretResponse.record;

      expect(recordWithoutLifespan).toEqual(expectedWithoutLifespan);
      expect(typeof store.record?.lifespan).toBe('number');
      expect(store.record?.lifespan).toBeGreaterThan(0); // Positive number check
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

      expect(store.record).toEqual(mockSecretResponse.record);
      expect(store.details).toEqual(mockSecretResponse.details);
      // No isLoading checks - that belongs in composable tests
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
          ...mockSecretRecord,
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

      it('handles missing is_owner field from API', async () => {
        const responseWithoutOwner = {
          ...mockSecretResponse,
          details: {
            ...mockSecretResponse.details,
            is_owner: undefined,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, responseWithoutOwner);
        await store.fetch('abc123');

        // Schema should default undefined to false
        expect(store.details?.is_owner).toBe(false);
      });
    });

    describe('lifespan field', () => {
      it('transforms TTL into human readable duration', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            secret_ttl: 86400, // 24 hours in seconds
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, response);
        await store.fetch('abc123');

        // Test that lifespan exists and is transformed to number
        expect(store.record?.lifespan).toBeDefined();
        expect(typeof store.record?.lifespan).toBe('number');
        expect(store.record?.lifespan).toBe(86400);
      });

      it('handles null TTL values', async () => {
        const response = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            secret_ttl: null,
            lifespan: null,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, response);
        await store.fetch('abc123');

        expect(store.record?.lifespan).toBeNull();
      });

      it('handles static lifespan from API', async () => {
        const staticLifespanResponse = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: '86400', // String that can be converted to number
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, staticLifespanResponse);
        await store.fetch('abc123');

        expect(typeof store.record?.lifespan).toBe('number');
        expect(store.record?.lifespan).toBe(86400);
      });

      it('handles null lifespan from API', async () => {
        const nullLifespanResponse = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: null,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, nullLifespanResponse);
        await store.fetch('abc123');

        expect(store.record?.lifespan).toBeNull();
      });

      it('handles missing lifespan field from API', async () => {
        const responseWithoutLifespan = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: undefined,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, responseWithoutLifespan);

        await store.fetch('abc123');

        // Schema transforms undefined to null
        expect(store.record?.lifespan).toBeNull();
      });

      it('should handle undefined lifespan gracefully', async () => {
        const responseWithUndefinedLifespan = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: undefined,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, responseWithUndefinedLifespan);

        // Schema transforms undefined to null, which is valid
        await store.fetch('abc123');

        // Store should have the record with lifespan as null
        expect(store.record?.lifespan).toBeNull();
      });

      it('handles undefined lifespan consistently across calls', async () => {
        // Start with null store state
        expect(store.record).toBeNull();

        const responseWithUndefinedLifespan = {
          ...mockSecretResponse,
          record: {
            ...mockSecretResponse.record,
            lifespan: undefined,
          },
        };

        axiosMock?.onGet('/api/v3/secret/abc123').reply(200, responseWithUndefinedLifespan);

        // Schema transforms undefined to null successfully
        await store.fetch('abc123');

        // Store should have the record with consistent null handling
        expect(store.record?.lifespan).toBeNull();
      });
    });
  });
});
