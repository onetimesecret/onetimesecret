import { withLoadingPlugin } from '@/plugins/pinia/withLoadingPlugin';
import { METADATA_STATUS, useMetadataStore } from '@/stores/metadataStore';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { createApp } from 'vue';

// Mock response schemas
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

// Mock error handler
vi.mock('@/composables/useErrorHandler', () => ({
  useErrorHandler: () => ({
    handleError: vi.fn().mockImplementation((error) => error),
  }),
}));

import { mockMetadataDetails, mockMetadataRecord } from '../fixtures/metadata';

const mockResponse = {
  record: mockMetadataRecord,
  details: mockMetadataDetails,
};

// Setup Vue app with Pinia
const app = createApp({});
const pinia = createPinia();
pinia.use(withLoadingPlugin);
app.use(pinia);

describe('metadataStore', () => {
  let store: ReturnType<typeof useMetadataStore>;
  let axiosMock: AxiosMockAdapter;

  beforeEach(() => {
    // Setup fresh Pinia instance
    setActivePinia(pinia);

    // Setup axios mock
    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance);

    // Initialize store
    store = useMetadataStore();
    store.init(axiosInstance);

    // Setup default mock responses if needed
    axiosMock.onGet(/\/api\/v2\/private\/.+/).reply(200, {
      record: {
        /* default mock record */
      },
      details: {
        /* default mock details */
      },
    });
  });

  afterEach(() => {
    // Clean up
    store.$reset();
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('error handling', () => {
    it('handles errors when fetching metadata by key', async () => {
      const testKey = 'test-key';

      axiosMock.onGet(`/api/v2/private/${testKey}`).replyOnce(404, {
        error: 'Not Found',
      });

      await expect(store.fetchOne(testKey)).rejects.toThrow();
      expect(store.error).toBeTruthy();
      expect(store.currentRecord).toBeNull();
      expect(store.currentDetails).toBeNull();
    });

    it('handles errors when fetching metadata list', async () => {
      axiosMock.onGet('/api/v2/private/recent').replyOnce(500, {
        error: 'Internal Server Error',
      });

      await expect(store.fetchList()).rejects.toThrow();
      expect(store.error).toBeTruthy();
      expect(store.records).toEqual([]);
    });

    it('handles errors when burning metadata', async () => {
      const testKey = 'test-key';
      store.currentRecord = {
        ...mockMetadataRecord,
        state: METADATA_STATUS.NEW,
        burned: false,
      };

      axiosMock.onPost(`/api/v2/private/${testKey}/burn`).replyOnce(404, {
        error: 'Not Found',
      });

      await expect(store.burn(testKey)).rejects.toThrow();
      expect(store.error).toBeTruthy();
    });
  });

  describe('plugins', () => {
    it('sets loading state during async operations', async () => {
      const testKey = 'test-key';

      // Setup delayed response
      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve([200, mockResponse]);
          }, 100);
        });
      });

      // Start the store operation
      const promise = store.fetchOne(testKey);

      // Check initial loading state
      expect(store.isLoading).toBe(true);

      // Wait for operation to complete
      await promise;

      // Verify final state
      expect(store.isLoading).toBe(false);
      expect(store.currentRecord).toEqual(mockMetadataRecord);
      expect(store.currentDetails).toEqual(mockMetadataDetails);
    });
  });

  describe('plugins (previous)', () => {
    it.skip('sets loading state during async operations', async () => {
      const testKey = 'test-key';
      axiosMock.get.mockImplementation(
        () => new Promise((resolve) => setTimeout(resolve, 10))
      );

      const promise = store.fetchOne(testKey);
      expect(store.isLoading).toBe(true);

      await promise;
      expect(store.isLoading).toBe(false);
    });
    it('notifies subscribers of state changes', async () => {
      // https://pinia.vuejs.org/core-concepts/actions.html#subscribing-to-actions
      const spy = vi.fn();
      store.$subscribe(spy);

      await store.fetchOne('test-key');

      expect(spy).toHaveBeenCalled();
    });
    it.skip('resets store state correctly', () => {
      store.records = { test: mockMetadataRecord };
      store.$reset();
      expect(store.records).toEqual({});
    });
  });

  describe('actions', () => {
    it('fetches metadata by key successfully', async () => {
      // Arrange
      const testKey = 'test-key';

      // Setup mock response using axios-mock-adapter
      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      });

      // Act
      await store.fetchOne(testKey);

      // Assert
      // First check store state properties
      expect(store.currentRecord).toEqual(mockMetadataRecord);
      expect(store.currentDetails).toEqual(mockMetadataDetails);
      // Then check if the record was stored in records map using the record's key
      // Note: We use mockMetadataRecord.key instead of testKey since the store
      // likely indexes by the record's actual key property
      expect(store.records[mockMetadataRecord.key]).toEqual(mockMetadataRecord);
    });

    it('handles errors when fetching metadata by key', async () => {
      // Arrange
      const testKey = 'test-key';

      // Setup mock error response
      // Note: Using replyOnce to ensure default success mock doesn't interfere
      axiosMock.onGet(`/api/v2/private/${testKey}`).replyOnce(
        404,
        {
          error: 'Not Found',
        },
        {
          'Content-Type': 'application/json',
        }
      );

      // Act & Assert
      // The store should throw an error when receiving a non-200 response
      await expect(store.fetchOne(testKey)).rejects.toThrow();

      // Verify the error state
      expect(store.records[testKey]).toBeUndefined();
      expect(store.currentRecord).toBeNull();
      expect(store.currentDetails).toBeNull();
    });
  });

  beforeEach(() => {
    setActivePinia(createPinia());
    store = useMetadataStore();
    store.init(axios);
    axiosMock.reset();
  });

  describe('fetchList', () => {
    it('handles errors when fetching all metadata', async () => {
      // Arrange
      axiosMock.onGet('/metadata').replyOnce(500, {
        error: 'Internal Server Error',
      });

      // Act & Assert
      await expect(store.fetchList()).rejects.toThrow();
      expect(store.records).toEqual([]);
    });
  });

  describe('create', () => {
    it('creates metadata successfully', async () => {
      const newMetadata: Metadata = {
        key: 'new-key',
        state: METADATA_STATUS.NEW,
        burned: false,
      };

      // Arrange
      axiosMock.onPost('/metadata').replyOnce(200, newMetadata);
      (responseSchemas.metadata.parse as Mock).mockReturnValue(newMetadata);

      // Act
      await store.create(newMetadata);

      // Assert
      expect(store.records[newMetadata.key]).toEqual(newMetadata);
    });

    it('handles errors when creating metadata', async () => {
      const newMetadata: Metadata = {
        key: 'new-key',
        state: METADATA_STATUS.NEW,
        burned: false,
      };

      // Arrange
      axiosMock.onPost('/metadata').replyOnce(400, {
        error: 'Bad Request',
      });

      // Act & Assert
      await expect(store.create(newMetadata)).rejects.toThrow();
      expect(store.records[newMetadata.key]).toBeUndefined();
    });
  });

  describe('update', () => {
    it('updates metadata successfully', async () => {
      const updatedMetadata: Metadata = {
        ...mockMetadataRecord,
        state: METADATA_STATUS.UPDATED,
      };

      // Arrange
      axiosMock
        .onPost(`/metadata/${updatedMetadata.key}`)
        .replyOnce(200, updatedMetadata);
      (responseSchemas.metadata.parse as Mock).mockReturnValue(updatedMetadata);

      // Act
      await store.update(updatedMetadata.key, updatedMetadata);

      // Assert
      expect(store.records[updatedMetadata.key]).toEqual(updatedMetadata);
    });
    describe('update', () => {
      let store: ReturnType<typeof useMetadataStore>;

      beforeEach(() => {
        setActivePinia(createPinia());
        store = useMetadataStore();
        store.init(axios); // Make sure store is initialized with axios instance
        vi.clearAllMocks();
      });

      it('handles errors when updating metadata', async () => {
        // Arrange
        const updatedMetadata: Metadata = {
          ...mockMetadataRecord,
          state: METADATA_STATUS.VIEWED,
        };
        const apiError = new ApiError(404, 'Not Found');

        // Setup mock using onPost instead of post directly
        axiosMock.onPost(`/metadata/${updatedMetadata.key}`).replyOnce(404, {
          error: 'Not Found',
        });

        // Act & Assert
        await expect(store.burn(updatedMetadata.key, updatedMetadata)).rejects.toThrow();

        // Assert
        expect(store.records[updatedMetadata.key]).not.toEqual(updatedMetadata);
        expect(store.error).toBeTruthy(); // Verify error state is set
      });
    });
  });
});
