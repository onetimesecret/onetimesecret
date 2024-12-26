import { withLoadingPlugin } from '@/plugins/pinia/withLoadingPlugin';
import { useMetadataStore } from '@/stores/metadataStore';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from 'vue';
import { mockMetadataDetails, mockMetadataRecord } from '../fixtures/metadata';

const app = createApp({});

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
  let mockResponse: {
    record: typeof mockMetadataRecord;
    details: typeof mockMetadataDetails;
  };

  beforeEach(async () => {
    const pinia = createPinia();
    pinia.use(withLoadingPlugin);
    app.use(pinia);
    setActivePinia(pinia);

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
});
