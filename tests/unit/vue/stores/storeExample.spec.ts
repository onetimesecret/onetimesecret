import axios, { type AxiosInstance } from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, defineStore, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// Minimal store implementation
const useTestStore = defineStore('test', {
  state: () => ({
    isLoading: false,
    data: null as any,
    error: null as Error | null,
  }),

  actions: {
    // Inject API client through closure
    _api: null as AxiosInstance | null,

    init(api: AxiosInstance) {
      this._api = api;
    },

    async _withLoading<T>(operation: () => Promise<T>): Promise<T> {
      this.isLoading = true;
      try {
        return await operation();
      } finally {
        this.isLoading = false;
      }
    },

    async fetchData(id: string) {
      return await this._withLoading(async () => {
        const response = await this._api!.get(`/api/data/${id}`);
        this.data = response.data;
        return response.data;
      });
    }
  }
});

describe('Store Testing Pattern', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useTestStore>;
  const mockData = { id: '123', value: 'test' };

  beforeEach(() => {
    // 1. Setup fresh Pinia instance
    setActivePinia(createPinia());

    // 2. Create fresh axios instance and mock
    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance, {
      onNoMatch: 'throwException'
    });

    // 3. Initialize store with mocked axios
    store = useTestStore();
    store.init(axiosInstance);
  });

  afterEach(() => {
    // Clean up
    axiosMock.reset();
    vi.clearAllMocks();
  });

  it('handles successful data fetch with loading state', async () => {
    // 1. Setup mock response BEFORE the request
    axiosMock
      .onGet('/api/data/123')
      .reply(200, mockData);

    // 2. Track loading states
    const loadingStates: boolean[] = [];
    store.$subscribe(() => {
      loadingStates.push(store.isLoading);
    });

    // 3. Execute and await the operation
    const result = await store.fetchData('123');

    // 4. Verify result
    expect(result).toEqual(mockData);
    expect(store.data).toEqual(mockData);

    // 5. Verify loading state lifecycle
    expect(loadingStates).toContain(true); // Was loading during operation
    expect(store.isLoading).toBe(false);   // Not loading after completion
  });

  it('handles network errors properly', async () => {
    // 1. Setup error response
    axiosMock
      .onGet('/api/data/123')
      .networkError();

    // 2. Verify error handling
    await expect(store.fetchData('123')).rejects.toThrow();
    expect(store.isLoading).toBe(false);
  });

  it('handles delayed responses correctly', async () => {
    // 1. Setup delayed response
    axiosMock
      .onGet('/api/data/123')
      .reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve([200, mockData]);
          }, 50);
        });
      });

    // 2. Start the request
    const promise = store.fetchData('123');

    // 3. Verify immediate loading state
    expect(store.isLoading).toBe(true);

    // 4. Wait for completion and verify final state
    await promise;
    expect(store.isLoading).toBe(false);
    expect(store.data).toEqual(mockData);
  });
});
