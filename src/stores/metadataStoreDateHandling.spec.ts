// src/stores/metadataStoreDateHandling.spec.ts

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
} from '../fixtures/metadata.fixture';

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
    /**
     * Add a handler to log all requests
     * NOTE: This will interfere with other tests when enabled.
     */
    //axiosMock.onAny().reply((config) => {
    //  console.log('Received request:', {
    //    method: config.method,
    //    url: config.url,
    //    headers: config.headers,
    //    data: config.data ? JSON.parse(config.data) : undefined,
    //  });
    //  return [404]; // This won't be reached if there's a more specific handler
    //});
    store = useMetadataStore();
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

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(TEST_DATES.now);
      expect(store.record?.updated).toEqual(TEST_DATES.now);
      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
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

      await store.fetch(testKey);

      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
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

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(expectedUTC);
    });
  });

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

    await store.fetch(testKey);

    expect(store.record?.created).toEqual(now);
    expect(store.record?.updated).toEqual(now);
    expect(store.record?.expiration).toEqual(expiration);
  });

  it('handles dates correctly when burning metadata', async () => {
    // ISSUE: testKey was using mockMetadataRecord.key ('testkey123')
    // but mock was set up for testKey variable directly ('testKey'),
    // causing a URL mismatch
    const testKey = mockMetadataRecord.key; // 'testkey123'
    const now = new Date('2024-12-25T16:06:54.000Z');

    const mockResponse = {
      record: {
        ...mockBurnedMetadataRecord,
        burned: now.toISOString(),
      },
      details: mockBurnedMetadataDetails,
    };

    store.record = mockMetadataRecord;

    // Fix: Match exact URL that will be used in request
    axiosMock
      .onPost(`/api/v2/private/testkey123/burn`, {
        continue: true,
      })
      .reply(200, mockResponse);

    await store.burn(testKey);

    // Verify the date was parsed correctly from ISO string to Date
    expect(store.record?.burned).toBeInstanceOf(Date);
    expect(store.record?.burned?.toISOString()).toBe(now.toISOString());
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

      store.record = mockMetadataRecord;

      // Updated mock setup with headers and exact matching
      axiosMock
        .onPost(
          `/api/v2/private/${testKey}/burn`,
          // Request body as exact match object
          { continue: true },
          // Headers as third argument
          {
            headers: {
              Accept: 'application/json, text/plain, */*',
              'content-type': 'application/json',
            },
          }
        )
        .reply(200, mockResponse);

      await store.burn(testKey);

      // Debug: Log all requests that were made
      // console.log('Mock history:', {
      //   post: axiosMock.history.post,
      //   all: axiosMock.history,
      // });

      // Check history after the request completes
      // expect(axiosMock.history.post.length).toBe(1);
      // expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({ continue: true });
      // expect(store.record?.burned).toEqual(TEST_DATES.now);

      expect(store.record?.burned).toEqual(TEST_DATES.now);
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

      store.record = mockMetadataRecord;

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

      expect(store.record?.burned).toEqual(TEST_DATES.now);
    });

    it('properly fails burning metadata if it has not been requested yet', async () => {
      const testKey = 'burnedkey';
      const mockResponse = {
        record: {
          ...mockMetadataRecord, // endpoit will raise error if we use burnedMetadataRecord (b/c it's already burned, canburn is false)
          created: TEST_DATES.now.toISOString(),
          updated: TEST_DATES.now.toISOString(),
          expiration: TEST_DATES.expiration.toISOString(),
          burned: TEST_DATES.now.toISOString(),
        },
        details: mockMetadataDetails,
      };

      // Log the exact mock we're setting up
      // console.log('Setting up mock for:', {
      //   url: `/api/v2/private/${testKey}/burn`,
      //   expectedData: { continue: true },
      // });

      axiosMock.onPost(`/api/v2/private/${testKey}/burn`).reply(function (config) {
        // Log the actual request for comparison
        // console.log('Actual request:', {
        //   url: config.url,
        //   method: config.method,
        //   data: JSON.parse(config.data),
        //   headers: config.headers,
        // });

        const data = JSON.parse(config.data);
        if (data.continue === true && data.passphrase === undefined) {
          return [200, mockResponse];
        }
        return [400];
      });

      await expect(async () => {
        await store.burn(testKey);
      }).rejects.toMatchObject({
        type: 'technical', // Error is classified as technical
        severity: 'error',
        message: 'No state metadata record',
      });

      // Debug: Log all requests that were made
      // console.log('Mock history (properly fails ):', {
      //   post: axiosMock.history.post,
      //   all: axiosMock.history,
      // });

      expect(store.record).toBeNull();
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

      await store.fetch(testKey);

      expect(store.record?.received).toEqual(TEST_DATES.now);
      expect(store.record?.state).toBe('received');
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

      await store.fetch(testKey);

      expect(store.record?.burned).toBeNull();
      expect(store.record?.received).toBeNull();
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

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(TEST_DATES.now);
    });

    it('handles invalid date formats gracefully', async () => {
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          burned: 'invalid-date', // burned transforms to dateNullable
          received: null, // received transforms to dateNullable as well
          expiration: TEST_DATES.expiration.toISOString(),
        },
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.burned).toBeNull();
      expect(store.record?.received).toBeNull();
      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('throws validation error for invalid required dates', async () => {
      // Test setup
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          ...mockMetadataRecord,
          created: 'invalid-date', // Invalid date that should trigger validation error
          updated: null,
        },
        details: mockMetadataDetails,
      };

      // Setup mock API response
      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      // Test the validation error
      await expect(async () => {
        await store.fetch(testKey);
      }).rejects.toMatchObject({
        type: 'technical', // Error is classified as technical
        severity: 'error',
        message: JSON.stringify(
          [
            {
              code: 'invalid_type',
              expected: 'date',
              received: 'null',
              path: ['record', 'created'],
              message: 'Expected date, received null',
            },
            {
              code: 'invalid_type',
              expected: 'date',
              received: 'null',
              path: ['record', 'updated'],
              message: 'Expected date, received null',
            },
          ],
          null,
          2
        ),
      });

      // Verify store state remains unchanged
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
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

      await store.fetch(testKey);

      // Verify all dates maintain UTC consistency
      Object.entries(utcDates).forEach(([key, value]) => {
        expect(store.record?.[key]).toEqual(new Date(value));
      });
    });
  });
});
