// tests/unit/vue/stores/metadataStore.spec.ts
import { ApplicationError } from '@/schemas';
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

  describe('fetch', () => {
    it('should fetch and validate metadata successfully', async () => {
      const testKey = mockMetadataRecord.key;
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.currentRecord).toEqual(mockMetadataRecord);
      expect(store.currentDetails).toEqual(mockMetadataDetails);
      expect(store.isLoading).toBe(false);
      expect(store.error).toBeUndefined();
    });

    it('should handle not found errors when fetching metadata', async () => {
      const testKey = mockMetadataRecord.key;
      const errorMessage = 'Request failed with status code 404';

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(404, {
        message: errorMessage,
      });

      try {
        await store.fetch(testKey);
        expect.fail('Expected error to be thrown');
      } catch (error) {
        const appError = error as ApplicationError;
        expect(appError.type).toBe('human');
        expect(appError.severity).toBe('error');
        expect(appError.message).toBe(errorMessage);
      }

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

      // Set initial state
      store.currentRecord = mockMetadataRecord;
      store.currentDetails = mockMetadataDetails;

      // Verify the exact URL and request body that will be sent
      axiosMock
        .onPost(`/api/v2/private/${testKey}/burn`, {
          passphrase: undefined,
          continue: true,
        })
        .reply(200, mockResponse);

      // Add error handling and logging for debugging
      try {
        const result = await store.burn(testKey);

        // Verify the request was actually made
        expect(axiosMock.history.post).toHaveLength(1);
        expect(axiosMock.history.post[0].url).toBe(`/api/v2/private/${testKey}/burn`);

        // Verify the state changes
        expect(store.currentRecord).toEqual(mockBurnedMetadataRecord);
        expect(store.currentDetails).toEqual(mockBurnedMetadataDetails);
        expect(store.error).toBeNull();

        // Verify the returned data
        expect(result).toEqual(mockResponse);
      } catch (error) {
        console.error('Test failed with error:', error);
        console.log('Mock history:', axiosMock.history);
        throw error;
      }
    });

    // Add test for invalid burn attempt
    it('should reject burn request for invalid state', async () => {
      const testKey = mockBurnedMetadataRecord.key;
      store.currentRecord = mockBurnedMetadataRecord;
      store.currentDetails = mockBurnedMetadataDetails;

      await expect(store.burn(testKey)).rejects.toThrow('Cannot burn this metadata');
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

      const promise = store.fetch(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await promise;

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
    });

    it('should handle loading state with errors', async () => {
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

      const promise = store.fetch(mockMetadataRecord.key);
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

      const promise = store.fetch(mockMetadataRecord.key);
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

  describe('error handling', () => {
    it('handles API errors correctly', async () => {
      // Simulate network error
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

      await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow();
      expect(store.error).toBeTruthy();
      expect(store.isLoading).toBe(false);
    });

    it('handles validation errors correctly', async () => {
      // Send invalid data that won't match schema
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(200, {
        record: { invalid: 'data' },
      });

      await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow();
      expect(store.error).toBeTruthy();
      expect(store.isLoading).toBe(false);
    });

    it('resets error state between requests', async () => {
      // First request fails
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();
      await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow();
      expect(store.error).toBeTruthy();

      // Second request succeeds
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(200, {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      });

      await store.fetch(mockMetadataRecord.key);
      expect(store.error).toBeNull();
    });
  });

  describe('metadataStore error handling and loading states', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useMetadataStore>;
    let notifySpy: ReturnType<typeof vi.fn>;
    let logSpy: ReturnType<typeof vi.fn>;
    let axiosInstance: ReturnType<typeof axios.create>;

    beforeEach(() => {
      axiosInstance = axios.create();
      axiosMock = new AxiosMockAdapter(axiosInstance);
      notifySpy = vi.fn();
      logSpy = vi.fn();

      const pinia = createTestingPinia({
        createSpy: vi.fn,
        stubActions: false,
      });

      store = useMetadataStore();
      store.init(axiosInstance);
    });

    describe('error propagation and classification', () => {
      it('propagates human-facing errors to UI', async () => {
        store = useMetadataStore();
        store.init(axiosInstance, { notify: notifySpy });

        // Simulate 404 - typically a human-facing error
        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(404, {
          message: 'Secret not found or expired',
        });

        await expect(store.fetch(mockMetadataRecord.key)).rejects.toMatchObject({
          type: 'human',
          severity: 'error',
          message: expect.stringContaining('Secret not found'),
        });

        expect(notifySpy).toHaveBeenCalledWith(
          expect.stringContaining('Secret not found'),
          'error'
        );
      });

      it('handles technical errors without user notification', async () => {
        store = useMetadataStore();
        store.init(axiosInstance, {
          notify: notifySpy,
          log: logSpy,
        });

        // Simulate network error - typically a technical error
        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

        await expect(store.fetch(mockMetadataRecord.key)).rejects.toMatchObject({
          type: 'technical',
          severity: 'error',
        });

        expect(notifySpy).not.toHaveBeenCalled();
        expect(logSpy).toHaveBeenCalledWith(expect.any(Error));
      });

      it('classifies validation errors correctly', async () => {
        store = useMetadataStore();
        store.init(axiosInstance, { notify: notifySpy });

        // Send malformed data that won't match schema
        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(200, {
          record: {
            invalidField: true,
            // Missing required fields
          },
        });

        const error = await store.fetch(mockMetadataRecord.key).catch((e) => e);

        expect(error).toMatchObject({
          type: 'technical',
          severity: 'error',
          message: expect.stringContaining('validation'),
        });
      });

      it('handles security-related errors appropriately', async () => {
        store = useMetadataStore();
        store.init(axiosInstance, { notify: notifySpy });

        // Simulate 403 Forbidden
        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(403, {
          message: 'Invalid authentication credentials',
        });

        const error = await store.fetch(mockMetadataRecord.key).catch((e) => e);

        expect(error).toMatchObject({
          type: 'security',
          severity: 'error',
        });

        expect(notifySpy).toHaveBeenCalledWith(expect.any(String), 'error');
      });
    });

    describe('loading state transitions', () => {
      it('follows correct loading state sequence for successful request', async () => {
        const loadingStates: boolean[] = [];
        const mockResponse = {
          record: mockMetadataRecord,
          details: mockMetadataDetails,
        };

        store.$subscribe(() => {
          loadingStates.push(store.isLoading);
        });

        axiosMock
          .onGet(`/api/v2/private/${mockMetadataRecord.key}`)
          .reply(200, mockResponse);

        expect(store.isLoading).toBe(false); // Initial state

        const promise = store.fetch(mockMetadataRecord.key);
        expect(store.isLoading).toBe(true); // Loading started

        await promise;

        expect(store.isLoading).toBe(false); // Loading complete
        expect(loadingStates).toEqual([true, false]); // Captures full transition
      });

      it('handles loading state properly with error', async () => {
        const loadingStates: boolean[] = [];

        store.$subscribe(() => {
          loadingStates.push(store.isLoading);
        });

        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(500);

        expect(store.isLoading).toBe(false); // Initial state

        await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow();

        expect(store.isLoading).toBe(false); // Should reset on error
        expect(loadingStates).toEqual([true, false]); // Should capture error transition
      });

      it('maintains loading state during concurrent requests', async () => {
        const loadingStates: boolean[] = [];

        store.$subscribe(() => {
          loadingStates.push(store.isLoading);
        });

        // Setup delayed responses
        axiosMock.onGet('/api/v2/private/key1').reply(() => {
          return new Promise((resolve) =>
            setTimeout(() => {
              resolve([200, { record: mockMetadataRecord }]);
            }, 50)
          );
        });

        axiosMock.onGet('/api/v2/private/key2').reply(() => {
          return new Promise((resolve) =>
            setTimeout(() => {
              resolve([200, { record: mockMetadataRecord }]);
            }, 25)
          );
        });

        // Start concurrent requests
        const promise1 = store.fetch('key1');
        const promise2 = store.fetch('key2');

        expect(store.isLoading).toBe(true);

        await Promise.all([promise1, promise2]);

        expect(store.isLoading).toBe(false);
        // Should only toggle once for concurrent requests
        expect(loadingStates.filter((state) => state === true).length).toBe(1);
      });
    });

    describe('error recovery', () => {
      it('recovers from error state on successful request', async () => {
        // First request fails
        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(500);

        await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow();

        // Second request succeeds
        axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(200, {
          record: mockMetadataRecord,
          details: mockMetadataDetails,
        });

        await store.fetch(mockMetadataRecord.key);
        expect(store.isLoading).toBe(false);
        expect(store.currentRecord).toBeTruthy();
      });
    });
  });
});
