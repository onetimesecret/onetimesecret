import { withLoadingPlugin } from '@/plugins/pinia/withLoadingPlugin';
import { ApiError } from '@/schemas/api/errors';
import { useMetadataStore } from '@/stores/metadataStore';
import type { AxiosInstance } from 'axios';
import axios from 'axios';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from 'vue';

import { mockMetadataRecord } from '../fixtures/metadata';

/**
 * Test environment setup utilities
 */
interface TestContext {
  store: ReturnType<typeof useMetadataStore>;
  axios: AxiosInstance;
}

const setupTestEnvironment = (): void => {
  const app = createApp({});
  const pinia = createPinia();
  pinia.use(withLoadingPlugin);
  app.use(pinia);
  setActivePinia(pinia);
};

/**
 * Mock utilities
 */
const createAxiosMock = () => {
  const axiosInstance = axios.create();
  vi.spyOn(axiosInstance, 'get');
  vi.spyOn(axiosInstance, 'post');
  vi.spyOn(axiosInstance, 'put');
  vi.spyOn(axiosInstance, 'delete');
  return axiosInstance;
};

const mockResponseSchemas = () => {
  vi.mock('@/schemas/api/responses', () => ({
    responseSchemas: {
      metadata: {
        parse: vi.fn().mockImplementation((data) => data),
      },
      metadataList: {
        parse: vi.fn().mockImplementation((data) => data),
      },
    },
  }));
};

describe('metadataStore', () => {
  let context: TestContext;

  beforeEach(() => {
    // Setup test environment
    setupTestEnvironment();
    mockResponseSchemas();

    // Initialize context
    context = {
      axios: createAxiosMock(),
      store: useMetadataStore(),
    };

    // Initialize store with mocked axios
    context.store.init(context.axios);
  });

  afterEach(() => {
    context.store.$reset();
    vi.clearAllMocks();
  });

  describe('fetching single metadata', () => {
    it('successfully fetches metadata by key', async () => {
      const testKey = 'test-key';

      vi.mocked(context.axios.get).mockResolvedValueOnce({
        data: mockMetadataRecord,
        status: 200,
      });

      await context.store.fetchOne(testKey);

      expect(context.axios.get).toHaveBeenCalledWith(`/api/v2/private/${testKey}`);
      expect(context.store.currentRecord).toEqual(mockMetadataRecord);
    });

    it('handles network errors appropriately', async () => {
      const testKey = 'test-key';
      const error = new ApiError(404, 'Not Found');

      vi.mocked(context.axios.get).mockRejectedValueOnce(error);

      await expect(context.store.fetchOne(testKey)).rejects.toThrow(error);
      expect(context.store.currentRecord).toBeNull();
    });

    it('manages loading state during fetch', async () => {
      const testKey = 'test-key';

      vi.mocked(context.axios.get).mockImplementationOnce(
        () =>
          new Promise((resolve) =>
            setTimeout(() => resolve({ data: mockMetadataRecord, status: 200 }), 100)
          )
      );

      const promise = context.store.fetchOne(testKey);
      expect(context.store.isLoading).toBe(true);

      await promise;
      expect(context.store.isLoading).toBe(false);
    });
  });

  describe('batch operations', () => {
    it('successfully fetches all metadata', async () => {
      const mockList = [mockMetadataRecord];

      vi.mocked(context.axios.get).mockResolvedValueOnce({
        data: { results: mockList },
        status: 200,
      });

      await context.store.fetchAll();

      expect(context.axios.get).toHaveBeenCalledWith('/api/v2/private/metadata');
      expect(Object.values(context.store.records)).toEqual(mockList);
    });
  });

  describe('mutations', () => {
    it('successfully creates new metadata', async () => {
      const newMetadata = { ...mockMetadataRecord, key: 'new-key' };

      vi.mocked(context.axios.post).mockResolvedValueOnce({
        data: newMetadata,
        status: 200,
      });

      await context.store.create(newMetadata);

      expect(context.axios.post).toHaveBeenCalledWith(
        '/api/v2/private/metadata',
        newMetadata
      );
      expect(context.store.records[newMetadata.key]).toEqual(newMetadata);
    });

    // Additional mutation tests...
  });
});
