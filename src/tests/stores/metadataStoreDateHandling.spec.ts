// src/tests/stores/metadataStoreDateHandling.spec.ts

// todo: before deleting opus files, review to add the blank testcases

// IMPORTANT: This test uses centralized test setup pattern
// DO NOT revert to individual axios.create() - use setupTestPinia() instead
import { useMetadataStore } from '@/stores/metadataStore';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';
import type { ComponentPublicInstance } from 'vue';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  mockBurnedMetadataDetails,
  mockBurnedMetadataRecord,
  mockMetadataDetails,
  mockMetadataRecord,
} from '../fixtures/metadata.fixture';

describe('Metadata Date Handling', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let store: ReturnType<typeof useMetadataStore>;
  let appInstance: ComponentPublicInstance | null;

  // Known test dates
  const TEST_DATES = {
    now: new Date('2024-12-25T16:06:54.000Z'),
    expiration: new Date('2024-12-26T00:06:54.000Z'),
    future: new Date('2024-12-27T16:06:54.000Z'),
  };

  // Unix timestamps in seconds (schema expects secondsToDate transform for created/updated/expiration)
  const TEST_TIMESTAMPS = {
    now: Math.floor(TEST_DATES.now.getTime() / 1000),
    expiration: Math.floor(TEST_DATES.expiration.getTime() / 1000),
    future: Math.floor(TEST_DATES.future.getTime() / 1000),
  };

  /**
   * Creates a mock metadata record for API responses with correct date formats.
   * Schema expects:
   * - created, updated, expiration: Unix timestamps in SECONDS (number)
   * - burned, received, shared, viewed: ISO strings or null (dateNullable transform)
   */
  const createMockMetadataResponse = (
    overrides: Partial<{
      key: string;
      created: number;
      updated: number;
      expiration: number;
      burned: string | null;
      received: string | null;
      state: string;
      [key: string]: unknown;
    }> = {}
  ) => {
    // Base record with timestamps in seconds (not Date objects)
    const baseRecord = {
      key: mockMetadataRecord.key,
      shortid: mockMetadataRecord.shortid,
      secret_identifier: mockMetadataRecord.secret_identifier,
      secret_shortid: mockMetadataRecord.secret_shortid,
      state: mockMetadataRecord.state,
      natural_expiration: mockMetadataRecord.natural_expiration,
      expiration_in_seconds: mockMetadataRecord.expiration_in_seconds,
      share_path: mockMetadataRecord.share_path,
      burn_path: mockMetadataRecord.burn_path,
      metadata_path: mockMetadataRecord.metadata_path,
      share_url: mockMetadataRecord.share_url,
      metadata_url: mockMetadataRecord.metadata_url,
      burn_url: mockMetadataRecord.burn_url,
      identifier: mockMetadataRecord.identifier,
      is_viewed: mockMetadataRecord.is_viewed,
      is_received: mockMetadataRecord.is_received,
      is_burned: mockMetadataRecord.is_burned,
      is_destroyed: mockMetadataRecord.is_destroyed,
      is_expired: mockMetadataRecord.is_expired,
      is_orphaned: mockMetadataRecord.is_orphaned,
      secret_ttl: mockMetadataRecord.secret_ttl,
      metadata_ttl: mockMetadataRecord.metadata_ttl,
      lifespan: mockMetadataRecord.lifespan,
      // Unix timestamps in seconds for date fields that use secondsToDate transform
      created: TEST_TIMESTAMPS.now,
      updated: TEST_TIMESTAMPS.now,
      expiration: TEST_TIMESTAMPS.expiration,
      // ISO strings for nullable date fields
      burned: null,
      received: null,
    };

    return {
      record: { ...baseRecord, ...overrides },
      details: mockMetadataDetails,
    };
  };

  const createBurnedMockResponse = (overrides: Record<string, unknown> = {}) => {
    const base = createMockMetadataResponse({
      key: 'burnedkey',
      state: 'burned',
      is_burned: true,
      burned: TEST_DATES.now.toISOString(),
      ...overrides,
    });
    return {
      ...base,
      details: mockBurnedMetadataDetails,
    };
  };

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    appInstance = setup.appInstance;

    // Initialize the store
    store = useMetadataStore();
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('Record Creation & Update Dates', () => {
    it('properly validates created and updated dates from Unix timestamps', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockMetadataResponse({
        created: TEST_TIMESTAMPS.now,
        updated: TEST_TIMESTAMPS.now,
        expiration: TEST_TIMESTAMPS.expiration,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(TEST_DATES.now);
      expect(store.record?.updated).toEqual(TEST_DATES.now);
      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('properly validates expiration date from Unix timestamp', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockMetadataResponse({
        expiration: TEST_TIMESTAMPS.expiration,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('handles different Unix timestamps correctly', async () => {
      const testKey = 'testkey123';
      // Use a different timestamp for created vs updated
      const mockResponse = createMockMetadataResponse({
        created: TEST_TIMESTAMPS.now,
        updated: TEST_TIMESTAMPS.future,
        expiration: TEST_TIMESTAMPS.expiration,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(TEST_DATES.now);
      expect(store.record?.updated).toEqual(TEST_DATES.future);
    });
  });

  it('handles dates correctly when fetching metadata', async () => {
    const testKey = mockMetadataRecord.key;
    const mockResponse = createMockMetadataResponse({
      key: testKey,
      created: TEST_TIMESTAMPS.now,
      updated: TEST_TIMESTAMPS.now,
      expiration: TEST_TIMESTAMPS.expiration,
    });

    axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

    await store.fetch(testKey);

    expect(store.record?.created).toEqual(TEST_DATES.now);
    expect(store.record?.updated).toEqual(TEST_DATES.now);
    expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
  });

  it('handles dates correctly when burning metadata', async () => {
    const testKey = mockMetadataRecord.key; // 'testkey123'
    const mockResponse = createBurnedMockResponse({
      key: testKey,
      burned: TEST_DATES.now.toISOString(),
    });

    store.record = mockMetadataRecord;

    axiosMock
      ?.onPost(`/api/v3/receipt/${testKey}/burn`, {
        continue: true,
      })
      .reply(200, mockResponse);

    await store.burn(testKey);

    // Verify the date was parsed correctly from ISO string to Date
    expect(store.record?.burned).toBeInstanceOf(Date);
    expect(store.record?.burned?.toISOString()).toBe(TEST_DATES.now.toISOString());
  });

  describe('State Change Dates', () => {
    it('properly validates burned date when burning metadata (strict headers)', async () => {
      const testKey = 'testkey123';
      const mockResponse = createBurnedMockResponse({
        key: testKey,
        burned: TEST_DATES.now.toISOString(),
      });

      store.record = mockMetadataRecord;

      // Behavior-focused mock - test the endpoint and request intent
      axiosMock
        ?.onPost(`/api/v3/receipt/${testKey}/burn`)
        .reply((config) => {
          // Verify the request body contains the expected data (behavior test)
          const requestData = JSON.parse(config.data);
          expect(requestData).toMatchObject({ continue: true });
          return [200, mockResponse];
        });

      await store.burn(testKey);

      expect(store.record?.burned).toEqual(TEST_DATES.now);
    });

    it('properly validates burned date when burning metadata (flexible)', async () => {
      const testKey = 'testkey123';
      const mockResponse = createBurnedMockResponse({
        key: testKey,
        burned: TEST_DATES.now.toISOString(),
      });

      store.record = mockMetadataRecord;

      // Updated mock setup with headers and exact matching
      axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(function (config) {
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
      const mockResponse = createMockMetadataResponse({
        key: testKey,
        burned: TEST_DATES.now.toISOString(),
      });

      axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(function (config) {
        const data = JSON.parse(config.data);
        if (data.continue === true && data.passphrase === undefined) {
          return [200, mockResponse];
        }
        return [400];
      });

      // store.record is null, so canBurn will be false
      await expect(async () => {
        await store.burn(testKey);
      }).rejects.toMatchObject({
        type: 'human', // Error is classified as human (canBurn check)
        severity: 'error',
        message: 'Cannot burn this metadata',
      });

      expect(store.record).toBeNull();
    });

    it('properly validates received date when receiving metadata', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockMetadataResponse({
        received: TEST_DATES.now.toISOString(),
        state: 'received',
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.received).toEqual(TEST_DATES.now);
      expect(store.record?.state).toBe('received');
    });

    it('handles null dates for optional date fields', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockMetadataResponse({
        burned: null,
        received: null,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.burned).toBeNull();
      expect(store.record?.received).toBeNull();
    });
  });

  describe('Date Transformations', () => {
    it('converts Unix timestamps to Date objects', async () => {
      const testKey = 'testkey123';
      // Schema expects Unix timestamps in seconds, not milliseconds
      const mockResponse = createMockMetadataResponse({
        created: TEST_TIMESTAMPS.now,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(TEST_DATES.now);
    });

    it('handles invalid date formats gracefully for nullable fields', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockMetadataResponse({
        burned: 'invalid-date', // burned transforms to dateNullable - should become null
        received: null, // received transforms to dateNullable as well
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.burned).toBeNull();
      expect(store.record?.received).toBeNull();
      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('throws validation error for invalid required dates', async () => {
      // Test setup - use raw record without helper to test invalid data
      const testKey = 'testkey123';
      const mockResponse = {
        record: {
          key: 'testkey123',
          shortid: 'abc123',
          state: 'new',
          natural_expiration: '24 hours',
          expiration_in_seconds: 86400,
          share_path: '/share/abc123',
          burn_path: '/burn/abc123',
          metadata_path: '/metadata/abc123',
          share_url: 'https://example.com/share/abc123',
          metadata_url: 'https://example.com/metadata/abc123',
          burn_url: 'https://example.com/burn/abc123',
          identifier: 'test-identifier',
          is_viewed: false,
          is_received: false,
          is_burned: false,
          is_destroyed: false,
          is_expired: false,
          is_orphaned: false,
          secret_ttl: null,
          metadata_ttl: null,
          lifespan: null,
          created: 'invalid-date', // Invalid - should trigger validation error
          updated: null,
          expiration: TEST_TIMESTAMPS.expiration,
          burned: null,
          received: null,
        },
        details: mockMetadataDetails,
      };

      // Setup mock API response
      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      // Test the validation error
      await expect(async () => {
        await store.fetch(testKey);
      }).rejects.toBeInstanceOf(Error);

      // Verify store state remains unchanged
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
    });

    it('maintains UTC consistency across transformations', async () => {
      const testKey = 'testkey123';
      // Use the helper with proper formats:
      // - Unix timestamps for created/updated/expiration
      // - ISO string for burned
      const mockResponse = createBurnedMockResponse({
        created: TEST_TIMESTAMPS.now,
        updated: TEST_TIMESTAMPS.now,
        expiration: TEST_TIMESTAMPS.expiration,
        burned: TEST_DATES.future.toISOString(),
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      // Verify dates are correctly transformed
      expect(store.record?.created).toEqual(TEST_DATES.now);
      expect(store.record?.updated).toEqual(TEST_DATES.now);
      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
      expect(store.record?.burned).toEqual(TEST_DATES.future);
    });
  });
});
