// tests/unit/vue/stores/metadataStore.spec.ts
import { useMetadataStore } from '@/stores/metadataStore';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { createPinia, setActivePinia } from 'pinia';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  mockBurnedMetadataDetails,
  mockBurnedMetadataRecord,
  mockMetadataDetails,
  mockMetadataRecord,
} from '../fixtures/metadata';

describe('metadataStore', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useMetadataStore>;

  beforeEach(() => {
    setActivePinia(createPinia());
    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance, {
      onNoMatch: 'throwException',
    });
    store = useMetadataStore();
    store.init(axiosInstance);
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('loading state management', () => {
    it('tracks loading state changes during operations', async () => {
      const testKey = 'testkey123';
      const loadingStates: boolean[] = [];

      // Watch for loading state changes
      watch(
        () => store.isLoading,
        (newValue) => {
          loadingStates.push(newValue);
        },
        { immediate: true }
      );

      // Add delay to mock response to ensure loading state is captured
      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve([200, mockResponse]);
          }, 50); // Small delay to ensure state change is captured
        });
      });

      await store.fetchOne(testKey);

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
    });

    it('handles loading state with delayed responses', async () => {
      const testKey = 'testkey123';

      // Add delay to mock response
      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => {
            resolve([200, mockResponse]);
          }, 50);
        });
      });

      const promise = store.fetchOne(testKey);

      // Need to wait a tick for the loading state to update
      await nextTick();
      expect(store.isLoading).toBe(true);

      await promise;
      expect(store.isLoading).toBe(false);
    });
  });

  // Update other test cases similarly to handle date fields
  describe('fetchOne', () => {
    const now = new Date('2024-12-25T16:06:54.000Z');
    const expiration = new Date('2024-12-26T00:06:54.000Z');
    let mockMetadataRecord;
    let mockBurnedMetadataRecord;
    beforeEach(() => {
      mockMetadataRecord = {
        ...mockMetadataRecord,
        created: now,
        updated: now,
        expiration: expiration,
      };

      mockBurnedMetadataRecord = {
        ...mockBurnedMetadataRecord,
        created: now,
        updated: now,
        expiration: expiration,
      };
    });

    it('fetches and validates metadata successfully', async () => {
      const testKey = 'testkey123';

      // Create dates with explicit values
      const now = new Date('2024-12-25T16:06:54.000Z');
      const expiration = new Date('2024-12-26T00:06:54.000Z');

      const localMockMetadataRecord = {
        ...mockMetadataRecord,
        created: now,
        updated: now,
        expiration: expiration,
        // ... other properties
      };

      const mockResponse = {
        record: {
          ...localMockMetadataRecord,
          // Use explicit ISO strings for dates
          created: now.toISOString(), // "2024-12-25T16:06:54.000Z"
          updated: now.toISOString(),
          expiration: expiration.toISOString(), // "2024-12-26T00:06:54.000Z"
          burned: null,
          received: null,
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      // Test exact date values
      expect(store.currentRecord?.created).toEqual(now);
      expect(store.currentRecord?.expiration).toEqual(expiration);
      expect(store.currentRecord).toEqual(mockMetadataRecord);
      expect(store.currentDetails).toEqual(mockMetadataDetails);
      expect(store.isLoading).toBe(false);
      expect(store.error).toBeNull();
    });
  });

  describe('burn', () => {
    it('burns metadata successfully', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          // Convert Date objects to ISO strings for the API response
          created: mockBurnedMetadataRecord.created.toISOString(),
          updated: mockBurnedMetadataRecord.updated.toISOString(),
          expiration: mockBurnedMetadataRecord.expiration.toISOString(),
          burned: mockBurnedMetadataRecord.burned?.toISOString() || null,
          received: mockBurnedMetadataRecord.received?.toISOString() || null,
        },
        details: mockBurnedMetadataDetails,
      };

      // Setup initial state
      store.currentRecord = mockMetadataRecord;
      store.currentDetails = mockMetadataDetails;

      axiosMock
        .onPost(`/api/v2/private/${testKey}/burn`, {
          passphrase: undefined,
          continue: true,
        })
        .reply(200, mockResponse);

      await store.burn(testKey);

      expect(store.currentRecord).toEqual(mockBurnedMetadataRecord);
      expect(store.currentDetails).toEqual(mockBurnedMetadataDetails);
      expect(store.isLoading).toBe(false);
    });

    it('burns metadata with passphrase', async () => {
      const testKey = 'testkey123';
      const passphrase = 'secret123';
      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          // Convert Date objects to ISO strings for the API response
          created: mockBurnedMetadataRecord.created.toISOString(),
          updated: mockBurnedMetadataRecord.updated.toISOString(),
          expiration: mockBurnedMetadataRecord.expiration.toISOString(),
          burned: mockBurnedMetadataRecord.burned?.toISOString() || null,
          received: mockBurnedMetadataRecord.received?.toISOString() || null,
        },
        details: mockBurnedMetadataDetails,
      };

      store.currentRecord = mockMetadataRecord;

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
  });

  describe('loading state management', () => {
    it('tracks loading state changes during operations', async () => {
      const testKey = 'testkey123';
      const loadingStates: boolean[] = [];

      axiosMock
        .onGet(`/api/v2/private/${testKey}`)
        .reply(200, { record: mockMetadataRecord, details: mockMetadataDetails });

      store.$subscribe(() => {
        loadingStates.push(store.isLoading);
      });

      await store.fetchOne(testKey);

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
    });

    it('handles loading state with delayed responses', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => resolve([200, mockResponse]), 50);
        });
      });

      const promise = store.fetchOne(testKey);
      expect(store.isLoading).toBe(true);

      await promise;
      expect(store.isLoading).toBe(false);
    });
  });
});
