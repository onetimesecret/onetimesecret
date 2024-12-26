import { withLoadingPlugin } from '@/plugins/pinia/withLoadingPlugin';
import { ApiError } from '@/schemas/api/errors';
import { Metadata } from '@/schemas/models'
import { useMetadataStore, METADATA_STATUS } from '@/stores/metadataStore';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi, type Mock } from 'vitest';
import { createApp } from 'vue';
import { ZodAny } from 'zod';

import { mockMetadataDetails, mockMetadataRecord } from '../fixtures/metadata';

// Pinia stores plugins don't work properly in tests unless there's app.
const app = createApp({});
const pinia = createPinia();
pinia.use(withLoadingPlugin);
app.use(pinia);

// Make pinia instance active for testing
setActivePinia(pinia);

// Create axios mock instance
const axiosMock = new AxiosMockAdapter(axios);

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

describe('metadataStore', () => {
  let store: ReturnType<typeof useMetadataStore>;
  let responseSchemas: ZodAny;

  let mockResponse: {
    record: typeof mockMetadataRecord;
    details: typeof mockMetadataDetails;
  };

  beforeEach(async () => {
    responseSchemas = await vi.importMock('@/schemas/api/responses');

    // Create fresh Pinia instance for each test

    store = useMetadataStore();

    mockResponse = {
      record: mockMetadataRecord,
      details: mockMetadataDetails,
    };

    axiosMock.reset();
    store.init(axios);

    // Setup default mock responses
    axiosMock.onGet(/\/api\/v2\/private\/.+/).reply(200, mockResponse);
    axiosMock.onPost(/\/api\/v2\/private\/.+/).reply(200, mockResponse);
  });

  afterEach(() => {
    store.$reset();
    axiosMock.reset();
    vi.clearAllMocks();
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

  describe('fetchAll', () => {
    let store: ReturnType<typeof useMetadataStore>;

    beforeEach(() => {
      setActivePinia(createPinia());
      store = useMetadataStore();
      vi.clearAllMocks();
    });

    it('fetches all metadata successfully', async () => {
      // Arrange
      const mockMetadataList: Metadata[] = [mockMetadataRecord];
      const apiResponse = { data: { results: mockMetadataList } };
      axiosMock.get.mockResolvedValue(apiResponse);
      (responseSchemas.metadataList.parse as Mock).mockReturnValue({
        results: mockMetadataList,
      });

      // Act
      await store.fetchAll();

      // Assert
      expect(axiosMock.get).toHaveBeenCalledWith('/metadata');
      expect(responseSchemas.metadataList.parse).toHaveBeenCalledWith(apiResponse.data);
      expect(Object.values(store.records)).toEqual(mockMetadataList);
    });

    it('handles errors when fetching all metadata', async () => {
      // Arrange
      const apiError = new ApiError(500, 'Internal Server Error');
      axiosMock.get.mockRejectedValue(apiError);

      // Act & Assert
      await expect(store.fetchAll()).rejects.toThrowError(apiError);

      // Assert
      expect(axiosMock.get).toHaveBeenCalledWith('/metadata');
      expect(store.records).toEqual({});
    });
  });

  describe('create', () => {
    let store: ReturnType<typeof useMetadataStore>;

    beforeEach(() => {
      setActivePinia(createPinia());
      store = useMetadataStore();
      vi.clearAllMocks();
    });

    it('creates metadata successfully', async () => {
      // Arrange
      const newMetadata: Metadata = {
        key: 'new-key',
        state: METADATA_STATUS.NEW,
        burned: false,
        // ...other properties
      };
      const apiResponse = { data: newMetadata };
      axiosMock.post.mockResolvedValue(apiResponse);
      (responseSchemas.metadata.parse as Mock).mockReturnValue(newMetadata);

      // Act
      await store.create(newMetadata);

      // Assert
      expect(axiosMock.post).toHaveBeenCalledWith('/metadata', newMetadata);
      expect(responseSchemas.metadata.parse).toHaveBeenCalledWith(apiResponse.data);
      expect(store.records[newMetadata.key]).toEqual(newMetadata);
    });

    it('handles errors when creating metadata', async () => {
      // Arrange
      const newMetadata: Metadata = {
        key: 'new-key',
        state: METADATA_STATUS.NEW,
        burned: false,
        // ...other properties
      };
      const apiError = new ApiError(400, 'Bad Request');
      axiosMock.post.mockRejectedValue(apiError);

      // Act & Assert
      await expect(store.create(newMetadata)).rejects.toThrowError(apiError);

      // Assert
      expect(axiosMock.post).toHaveBeenCalledWith('/metadata', newMetadata);
      expect(store.records[newMetadata.key]).toBeUndefined();
    });
  });

  describe('update', () => {
    let store: ReturnType<typeof useMetadataStore>;

    beforeEach(() => {
      setActivePinia(createPinia());
      store = useMetadataStore();
      vi.clearAllMocks();
    });

    it('updates metadata successfully', async () => {
      // Arrange
      const updatedMetadata: Metadata = {
        ...mockMetadataRecord,
        state: METADATA_STATUS.UPDATED,
      };
      const apiResponse = { data: updatedMetadata };
      axiosMock.post.mockResolvedValue(apiResponse);
      (responseSchemas.metadata.parse as Mock).mockReturnValue(updatedMetadata);

      // Act
      await store.update(updatedMetadata.key, updatedMetadata);

      // Assert
      expect(axiosMock.post).toHaveBeenCalledWith(
        `/metadata/${updatedMetadata.key}`,
        updatedMetadata
      );
      expect(responseSchemas.metadata.parse).toHaveBeenCalledWith(apiResponse.data);
      expect(store.records[updatedMetadata.key]).toEqual(updatedMetadata);
    });

    it('handles errors when updating metadata', async () => {
      // Arrange
      const updatedMetadata: Metadata = {
        ...mockMetadataRecord,
        state: METADATA_STATUS.UPDATED,
      };
      const apiError = new ApiError(404, 'Not Found');
      axiosMock.post.mockRejectedValue(apiError);

      // Act & Assert
      await expect(
        store.update(updatedMetadata.key, updatedMetadata)
      ).rejects.toThrowError(apiError);

      // Assert
      expect(axiosMock.post).toHaveBeenCalledWith(
        `/metadata/${updatedMetadata.key}`,
        updatedMetadata
      );
      expect(store.records[updatedMetadata.key]).not.toEqual(updatedMetadata);
    });
  });
});
