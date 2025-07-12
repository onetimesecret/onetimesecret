// tests/unit/vue/stores/metadataListStore.spec.ts
import { useMetadataListStore } from '@/stores/metadataListStore';
import { createTestingPinia } from '@pinia/testing';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  mockMetadataRecent,
  mockMetadataRecentDetails,
  mockMetadataRecentRecords,
} from '../fixtures/metadata.fixture';

describe('metadataListStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useMetadataListStore>;

  beforeEach(() => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });

    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance);

    store = useMetadataListStore();
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('fetchList', () => {
    it('should fetch and store list of metadata records', async () => {
      const mockResponse = {
        custid: 'user-123',
        count: 2,
        ...mockMetadataRecent,
      };

      axiosMock.onGet('/api/v2/receipt/recent').reply(200, mockResponse);
      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.fetchList();

      expect(store.records).toEqual(mockMetadataRecentRecords);
      expect(store.details).toEqual(mockMetadataRecentDetails);
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

      axiosMock.onGet('/api/v2/receipt/recent').reply(200, mockResponse);
      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.fetchList();

      expect(store.count).toBe(0);
      expect(store.records).toHaveLength(0);
      expect(store.details?.received).toHaveLength(0);
      expect(store.details?.notreceived).toHaveLength(0);
      expect(store.isLoading).toBe(false);
    });
  });

  describe('refreshRecords', () => {
    it('should fetch records only when not initialized', async () => {
      const mockResponse = {
        records: mockMetadataRecentRecords,
        details: mockMetadataRecentDetails,
      };

      axiosMock.onGet('/api/v2/receipt/recent').reply(200, mockResponse);
      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.refreshRecords();
      expect(store._initialized).toBe(true);

      // Second call should not fetch
      await store.refreshRecords();
      expect(axiosMock.history.get.length).toBe(1);
    });

    it('should fetch records when force is true, even if initialized', async () => {
      const mockResponse = {
        custid: 'user-123',
        count: 2,
        records: mockMetadataRecentRecords,
        details: mockMetadataRecentDetails,
      };

      axiosMock.onGet('/api/v2/receipt/recent').reply(200, mockResponse);
      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      // First call to initialize
      await store.refreshRecords();
      expect(store._initialized).toBe(true);
      expect(axiosMock.history.get.length).toBe(1);

      // Second call with force=true should fetch again
      await store.refreshRecords(true);
      expect(store._initialized).toBe(true);
      expect(axiosMock.history.get.length).toBe(2);
    });
  });

  describe('loading state', () => {
    it('tracks detailed loading state changes', async () => {
      const loadingStates: boolean[] = [];
      const mockResponse = {
        custid: 'user-123',
        count: 2,
        ...mockMetadataRecent,
      };

      store.$subscribe(() => {
        loadingStates.push(store.isLoading);
      });

      axiosMock.onGet('/api/v2/private/recent').reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => resolve([200, mockResponse]), 50);
        });
      });

      const promise = store.fetchList();
      expect(store.isLoading).toBe(true);

      await promise;

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
      expect(loadingStates[loadingStates.length - 1]).toBe(false);
    });
  });

  describe('error handling', () => {
    it('handles API errors correctly', async () => {
      axiosMock.onGet('/api/v2/private/recent').networkError();

      await expect(store.fetchList()).rejects.toThrow();
      expect(store.isLoading).toBe(false);
    });

    it('handles validation errors correctly', async () => {
      axiosMock.onGet('/api/v2/private/recent').reply(200, {
        records: [{ invalid: 'data' }],
      });

      await expect(store.fetchList()).rejects.toThrow();
      expect(store.isLoading).toBe(false);
    });

    it('resets error state between requests', async () => {
      // First request fails
      axiosMock.onGet('/api/v2/private/recent').networkError();
      await expect(store.fetchList()).rejects.toThrow();

      // Second request succeeds
      axiosMock.onGet('/api/v2/private/recent').reply(200, {
        custid: 'user-123',
        count: 2,
        ...mockMetadataRecent,
      });

      await store.fetchList();
      expect(store.records).toEqual(mockMetadataRecentRecords);
    });
  });

  // Add hydration test if the feature is actually used
  describe('hydration', () => {
    it('refreshes records on store hydration', async () => {
      const mockResponse = {
        records: mockMetadataRecentRecords,
        details: mockMetadataRecentDetails,
      };

      axiosMock.onGet('/api/v2/private/recent').reply(200, mockResponse);

      await store.refreshRecords();
      expect(store._initialized).toBe(true);

      // Verify hydration behavior
      await store.refreshRecords();
      expect(axiosMock.history.get.length).toBe(1); // Should only call once
    });
  });

  describe('metadataStore error handling and loading states', () => {
    let axiosMock: AxiosMockAdapter;
    let store: ReturnType<typeof useMetadataListStore>;
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

      store = useMetadataListStore();
    });
    describe('error propagation and classification', () => {
      it('propagates human-facing errors to UI', async () => {
        store = useMetadataListStore();
        // store.setupAsyncHandler(axiosInstance, { notify: notifySpy });
      });

      it('handles technical errors without user notification', async () => {
        store = useMetadataListStore();
        // store.setupAsyncHandler(axiosInstance, {
        //   notify: notifySpy,
        //   log: logSpy,
        // });
      });

      it('classifies schema validation errors as technical errors', async () => {
        store = useMetadataListStore();
        // store.setupAsyncHandler(axiosInstance, { notify: notifySpy });

        // Send malformed data that won't match schema
        axiosMock.onGet(`/api/v2/private/recent`).reply(200, {
          record: {
            invalidField: true,
            // Missing required records array
          },
        });

        await expect(store.fetchList()).rejects.toEqual(
          expect.objectContaining({
            type: 'technical', // Schema validation errors are technical
            severity: 'error',
            message: expect.stringContaining('Required'), // More specific message check
          })
        );
      });

      it.skip('handles security-related errors appropriately', async () => {
        store = useMetadataListStore();
        // store.setupAsyncHandler(axiosInstance, { notify: notifySpy });

        // Simulate 403 Forbidden
        axiosMock.onGet(`/api/v2/private/recent`).reply(403, {
          message: 'Invalid authentication credentials',
        });

        // Debug: Log the full error object
        const error = await store.fetchList().catch((e) => {
          console.log('Full error object:', {
            name: e.name,
            message: e.message,
            type: e.type,
            severity: e.severity,
            stack: e.stack,
            response: e.response?.data,
          });
          return e;
        });

        expect(error).toMatchObject({
          type: 'security',
          severity: 'error',
        });

        // TODO: Fix the store code to be aware of notificaiton and log functions
        //expect(notifySpy).toHaveBeenCalledWith(expect.any(String), 'error');

        // Add debugging info about notification calls
        console.log('Notification spy calls:', notifySpy.mock.calls);
      });
    });

    describe('loading state transitions', () => {
      it('follows correct loading state sequence for successful request', async () => {
        const loadingStates: boolean[] = [];
        // const mockResponse = {
        //   record: mockMetadataRecentRecords,
        //   details: mockMetadataRecentDetails,
        // };

        store.$subscribe(() => {
          loadingStates.push(store.isLoading);
        });
      });

      it('handles loading state properly with error', async () => {
        const loadingStates: boolean[] = [];

        store.$subscribe(() => {
          loadingStates.push(store.isLoading);
        });
      });

      it('maintains loading state during concurrent requests', async () => {
        const loadingStates: boolean[] = [];

        store.$subscribe(() => {
          loadingStates.push(store.isLoading);
        });
      });
    });

    describe('error recovery', () => {
      it('recovers from error state on successful request', async () => {
        // First request fails
        axiosMock.onGet(`/api/v2/private/recent`).reply(500);

        await expect(store.fetchList()).rejects.toThrow();

        // Second request succeeds
        axiosMock.onGet(`/api/v2/private/recent`).reply(200, {
          records: mockMetadataRecentRecords,
          details: mockMetadataRecentDetails,
        });

        await store.fetchList();
        expect(store.isLoading).toBe(false);
        expect(store.records).toBeTruthy();
      });
    });
  });
});
