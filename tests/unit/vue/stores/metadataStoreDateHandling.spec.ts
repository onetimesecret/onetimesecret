// tests/unit/vue/stores/metadataStoreDateHandling.spec.ts

// todo: before deleting opus files, review to add the blank testcases

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

describe('Metadata Date Handling', () => {
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useMetadataStore>;

  // Known test dates
  const TEST_DATES = {
    now: new Date('2024-12-25T16:06:54.000Z'),
    expiration: new Date('2024-12-26T00:06:54.000Z'),
    future: new Date('2024-12-27T16:06:54.000Z'),
  };

  beforeEach(() => {
    setActivePinia(createPinia());
    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance, {
      onNoMatch: 'throwException',
      delayResponse: 0,
    });
    // Add a handler to log all requests
    // axiosMock.onAny().reply((config) => {
    //   console.log('Received request:', {
    //     method: config.method,
    //     url: config.url,
    //     headers: config.headers,
    //     data: config.data ? JSON.parse(config.data) : undefined,
    //   });
    //   return [404]; // This won't be reached if there's a more specific handler
    // });
    store = useMetadataStore();
    store.init(axiosInstance);
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('Record Creation & Update Dates', () => {
    it('properly validates created and updated dates from ISO string', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          updated: TEST_DATES.now.toISOString(),
          expiration: TEST_DATES.expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.created).toEqual(TEST_DATES.now);
      expect(store.currentRecord?.updated).toEqual(TEST_DATES.now);
      expect(store.currentRecord?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('properly validates expiration date from ISO string', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          updated: TEST_DATES.now.toISOString(),
          expiration: TEST_DATES.expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('handles timezone conversions correctly', async () => {
      const testKey = 'testkey123';
      // Using explicit timezone offset
      const dateInPST = '2024-12-25T08:06:54-08:00';
      const expectedUTC = new Date('2024-12-25T16:06:54.000Z');

      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: dateInPST,
          expiration: TEST_DATES.expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.created).toEqual(expectedUTC);
    });
  });

  describe('State Change Dates', () => {
    it('properly validates burned date when burning metadata (strict headers)', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          updated: TEST_DATES.now.toISOString(),
          expiration: TEST_DATES.expiration.toISOString(),
          burned: TEST_DATES.now.toISOString(),
        },
        details: mockBurnedMetadataDetails,
      };

      store.currentRecord = mockMetadataRecord;

      // Updated mock setup with headers and exact matching
      axiosMock
        .onPost(
          `/api/v2/private/${testKey}/burn`,
          { passphrase: undefined, continue: true },
          {
            headers: {
              Accept: 'application/json, text/plain, */*',
              'Content-Type': 'application/json',
            },
          }
        )
        .reply(200, mockResponse);

      await store.burn(testKey);

      expect(store.currentRecord?.burned).toEqual(TEST_DATES.now);
    });

    it('properly validates burned date when burning metadata (flexible)', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          updated: TEST_DATES.now.toISOString(),
          expiration: TEST_DATES.expiration.toISOString(),
          burned: TEST_DATES.now.toISOString(),
        },
        details: mockBurnedMetadataDetails,
      };

      store.currentRecord = mockMetadataRecord;

      // Updated mock setup with headers and exact matching
      axiosMock.onPost(`/api/v2/private/${testKey}/burn`).reply(function (config) {
        // Verify the body matches what we expect
        const data = JSON.parse(config.data);
        if (data.continue === true && data.passphrase === undefined) {
          return [200, mockResponse];
        }
        return [400];
      });

      await store.burn(testKey);

      expect(store.currentRecord?.burned).toEqual(TEST_DATES.now);
    });
    it('properly validates burned date when burning metadata (alt)', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          updated: TEST_DATES.now.toISOString(),
          expiration: TEST_DATES.expiration.toISOString(),
          burned: TEST_DATES.now.toISOString(),
        },
        details: mockBurnedMetadataDetails,
      };
      // Log the exact mock we're setting up
      console.log('Setting up mock for:', {
        url: `/api/v2/private/${testKey}/burn`,
        expectedData: { passphrase: undefined, continue: true },
      });

      axiosMock.onPost(`/api/v2/private/${testKey}/burn`).reply(function (config) {
        // Log the actual request for comparison
        console.log('Actual request:', {
          url: config.url,
          method: config.method,
          data: JSON.parse(config.data),
          headers: config.headers,
        });

        const data = JSON.parse(config.data);
        if (data.continue === true && data.passphrase === undefined) {
          return [200, mockResponse];
        }
        return [400];
      });

      await store.burn(testKey);
      expect(store.currentRecord?.burned).toEqual(TEST_DATES.now);
    });

    it('properly validates received date when receiving metadata', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          received: TEST_DATES.now.toISOString(),
          state: 'received',
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.received).toEqual(TEST_DATES.now);
      expect(store.currentRecord?.state).toBe('received');
    });

    it('handles null dates for optional date fields', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: TEST_DATES.now.toISOString(),
          burned: null,
          received: null,
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.burned).toBeNull();
      expect(store.currentRecord?.received).toBeNull();
    });
  });

  describe('Date Transformations', () => {
    it('converts string timestamps to Date objects', async () => {
      const testKey = 'testkey123';
      const timestamp = TEST_DATES.now.getTime().toString();

      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: timestamp,
          expiration: TEST_DATES.expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.created).toEqual(TEST_DATES.now);
    });

    it('handles invalid date formats gracefully', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: 'invalid-date',
          updated: null,
          expiration: TEST_DATES.expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      expect(store.currentRecord?.created).toBeNull();
      expect(store.currentRecord?.updated).toBeNull();
      expect(store.currentRecord?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('maintains UTC consistency across transformations', async () => {
      const testKey = 'testkey123';
      const utcDates = {
        created: TEST_DATES.now.toISOString(),
        updated: TEST_DATES.now.toISOString(),
        expiration: TEST_DATES.expiration.toISOString(),
        burned: TEST_DATES.future.toISOString(),
      };

      const mockResponse = {
        record: {
          ...mockBurnedMetadataRecord,
          ...utcDates,
        },
        details: mockBurnedMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetchOne(testKey);

      // Verify all dates maintain UTC consistency
      Object.entries(utcDates).forEach(([key, value]) => {
        expect(store.currentRecord?.[key]).toEqual(new Date(value));
      });
    });
  });
});
