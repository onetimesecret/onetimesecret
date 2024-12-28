// tests/unit/vue/stores/metadataStore.spec.ts
import { useMetadataStore } from '@/stores/metadataStore';
import { createTestingPinia } from '@pinia/testing';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  createMetadataWithPassphrase,
  mockBurnedMetadataDetails,
  mockBurnedMetadataRecord,
  mockMetadataDetails,
  mockMetadataRecent,
  mockMetadataRecord,
} from '../fixtures/metadata';

/**
 * NOTE: These tests run using a simple Axios mock adapter to simulate API responses. They do not
 * actually make network requests. However, the adapter also does not include the full Axios
 * request/response lifecycle (our interceptors in utils/api) which can affect how errors are
 * propagated. This is a limitation of the current test setup.
 */
describe('metadataStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useMetadataStore>;

  beforeEach(() => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });

    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance);

    store = useMetadataStore();
    store.init(axiosInstance);
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('fetchOne', () => {
    it('should fetch and validate metadata successfully', async () => {
      const testKey = mockMetadataRecord.key;
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord).toEqual(mockMetadataRecord);
      expect(store.currentDetails).toEqual(mockMetadataDetails);
      expect(store.isLoading).toBe(false);
      expect(store.error).toBeNull();
    });

    it('should handle not found errors when fetching metadata', async () => {
      const testKey = mockMetadataRecord.key;
      const errorMessage = 'Secret not found or already viewed';

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(404, {
        message: errorMessage,
      });

      const result = await store.fetchOne(testKey);

      expect(result).toEqual({
        status: 'error',
        error: {
          kind: 'not_found',
          message: errorMessage,
        },
      });

      // Side effects should still occur
      expect(store.isLoading).toBe(false);
      expect(store.currentRecord).toBeNull();
    });
  });

  describe('fetchList', () => {
    it('should fetch and store list of metadata records', async () => {
      const mockResponse = {
        custid: 'user-123',
        count: 2,
        ...mockMetadataRecent,
      };

      // console.log('Mock Data Being Used:', mockResponse);

      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.fetchList();

      // console.log('Store State in Test:', {
      //   records: store.records,
      //   details: store.details,
      //   count: store.count,
      //   isLoading: store.isLoading,
      // });

      expect(store.records).toEqual(mockMetadataRecent.records);
      expect(store.details).toEqual(mockMetadataRecent.details);
      expect(store.isLoading).toBe(false);
    });

    it('should handle empty metadata list', async () => {
      const mockResponse = {
        custid: 'user-123',
        count: 0,
        records: [],
        details: {
          type: 'list',
          since: 3600 * 24 * 7,
          now: new Date(),
          has_items: false,
          received: [],
          notreceived: [],
        },
      };

      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.fetchList();

      expect(store.count).toBe(0);
      expect(store.records).toHaveLength(0);
      expect(store.details.received).toHaveLength(0);
      expect(store.details.notreceived).toHaveLength(0);
      expect(store.isLoading).toBe(false);
    });
  });

  describe('burn', () => {
    it('should burn metadata successfully', async () => {
      const testKey = mockMetadataRecord.key;
      const mockResponse = {
        record: mockBurnedMetadataRecord,
        details: mockBurnedMetadataDetails,
      };

      store.currentRecord = mockMetadataRecord;

      axiosMock
        .onPost(`/api/v2/private/${testKey}/burn`, {
          passphrase: undefined,
          continue: true,
        })
        .reply(200, mockResponse);

      await store.burn(testKey);

      expect(store.currentRecord).toEqual(mockBurnedMetadataRecord);
      expect(store.currentDetails).toEqual(mockBurnedMetadataDetails);
    });

    it('should burn metadata with passphrase', async () => {
      const testKey = mockMetadataRecord.key;
      const passphrase = 'secret123';
      const { record, details } = createMetadataWithPassphrase(passphrase);

      const mockResponse = {
        record: mockBurnedMetadataRecord,
        details: mockBurnedMetadataDetails,
      };

      store.currentRecord = record;
      store.currentDetails = details;

      axiosMock
        .onPost(`/api/v2/private/${testKey}/burn`, {
          passphrase,
          continue: true,
        })
        .reply(200, mockResponse);

      await store.burn(testKey, passphrase);

      expect(store.currentRecord).toEqual(mockBurnedMetadataRecord);
      expect(store.currentDetails).toEqual(mockBurnedMetadataDetails);
    });

    it('should handle errors when burning invalid metadata', async () => {
      const testKey = mockBurnedMetadataRecord.key;
      store.currentRecord = mockBurnedMetadataRecord;

      await expect(store.burn(testKey)).rejects.toThrow('Cannot burn this metadata');
      expect(store.error).toBeTruthy();
    });
  });

  describe('canBurn getter', () => {
    it('returns false when no current record exists', () => {
      store.currentRecord = null;
      expect(store.canBurn).toBe(false);
    });

    it('returns true for NEW state', () => {
      store.currentRecord = mockMetadataRecord;
      expect(store.canBurn).toBe(true);
    });

    it('returns false for BURNED state', () => {
      store.currentRecord = mockBurnedMetadataRecord;
      expect(store.canBurn).toBe(false);
    });
  });

  describe('loading state', () => {
    it('should track loading state during async operations', async () => {
      const loadingStates: boolean[] = [];
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => resolve([200, mockResponse]), 50);
        });
      });

      store.$subscribe(() => {
        loadingStates.push(store.isLoading);
      });

      const promise = store.fetchOne(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await promise;

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
    });

    it('should handle loading state with errors', async () => {
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

      const promise = store.fetchOne(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await expect(promise).rejects.toThrow();
      expect(store.isLoading).toBe(false);
    });

    // Add to loading state describe block
    it('tracks detailed loading state changes', async () => {
      const loadingStates: boolean[] = [];
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      // Subscribe to catch all state changes
      store.$subscribe(() => {
        loadingStates.push(store.isLoading);
      });

      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => resolve([200, mockResponse]), 50);
        });
      });

      const promise = store.fetchOne(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await promise;

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
      expect(loadingStates[loadingStates.length - 1]).toBe(false);
    });
  });

  describe('refreshRecords', () => {
    it('should fetch records only when not initialized', async () => {
      const mockResponse = {
        records: [mockMetadataRecord],
        details: { total: 1, page: 1, per_page: 10 },
      };

      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.refreshRecords();
      expect(store.initialized).toBe(true);

      // Second call should not fetch
      await store.refreshRecords();
      expect(axiosMock.history.get.length).toBe(1);
    });
  });

  describe('date handling', () => {
    it('handles dates correctly when fetching metadata', async () => {
      const testKey = mockMetadataRecord.key;
      const now = new Date('2024-12-25T16:06:54.000Z');
      const expiration = new Date('2024-12-26T00:06:54.000Z');

      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: now.toISOString(),
          updated: now.toISOString(),
          expiration: expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.created).toEqual(now);
      expect(store.currentRecord?.updated).toEqual(now);
      expect(store.currentRecord?.expiration).toEqual(expiration);
    });

    it('handles dates correctly when burning metadata', async () => {
      const testKey = mockMetadataRecord.key;
      const now = new Date('2024-12-25T16:06:54.000Z');

      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          burned: now.toISOString(),
        },
        details: mockBurnedMetadataDetails,
      };

      store.currentRecord = mockMetadataRecord;

      axiosMock
        .onPost(`/api/v2/private/${testKey}/burn`, {
          passphrase: undefined,
          continue: true,
        })
        .reply(200, mockResponse);

      await store.burn(testKey);

      expect(store.currentRecord?.burned).toEqual(now);
    });
  });

  // Add hydration test if the feature is actually used
  describe('hydration', () => {
    it('refreshes records on store hydration', async () => {
      const mockResponse = {
        records: [mockMetadataRecord],
        details: { total: 1, page: 1, per_page: 10 },
      };

      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.refreshRecords();
      expect(store.initialized).toBe(true);

      // Verify hydration behavior
      await store.refreshRecords();
      expect(axiosMock.history.get.length).toBe(1); // Should only call once
    });
  });
});
