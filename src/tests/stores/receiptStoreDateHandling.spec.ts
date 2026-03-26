// src/tests/stores/receiptStoreDateHandling.spec.ts

// todo: before deleting opus files, review to add the blank testcases

// IMPORTANT: This test uses centralized test setup pattern
// DO NOT revert to individual axios.create() - use setupTestPinia() instead
import { useReceiptStore } from '@/shared/stores/receiptStore';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';
import type { ComponentPublicInstance } from 'vue';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import {
  mockBurnedReceiptDetails,
  mockBurnedReceiptRecord,
  mockReceiptDetails,
  mockReceiptRecord,
} from '../fixtures/receipt.fixture';

describe('Receipt Date Handling', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let store: ReturnType<typeof useReceiptStore>;
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
   * Creates a mock receipt record for V3 API responses.
   * V3 schema expects:
   * - created, updated, expiration: Unix timestamps in SECONDS (number)
   * - burned, received, shared, viewed, previewed, revealed: number | null (toDateNullish)
   */
  const createMockReceiptResponse = (
    overrides: Partial<{
      key: string;
      created: number;
      updated: number;
      expiration: number;
      burned: number | null;
      received: number | null;
      shared: number | null;
      viewed: number | null;
      previewed: number | null;
      revealed: number | null;
      state: string;
      is_burned: boolean;
      [key: string]: unknown;
    }> = {}
  ) => {
    const baseRecord = {
      key: mockReceiptRecord.key,
      shortid: mockReceiptRecord.shortid,
      secret_identifier: mockReceiptRecord.secret_identifier,
      secret_shortid: mockReceiptRecord.secret_shortid,
      state: mockReceiptRecord.state,
      natural_expiration: mockReceiptRecord.natural_expiration,
      expiration_in_seconds: mockReceiptRecord.expiration_in_seconds,
      share_path: mockReceiptRecord.share_path,
      burn_path: mockReceiptRecord.burn_path,
      receipt_path: mockReceiptRecord.receipt_path,
      share_url: mockReceiptRecord.share_url,
      receipt_url: mockReceiptRecord.receipt_url,
      burn_url: mockReceiptRecord.burn_url,
      identifier: mockReceiptRecord.identifier,
      // V3 canonical boolean fields (replaces deprecated is_viewed/is_received)
      is_previewed: mockReceiptRecord.is_previewed,
      is_revealed: mockReceiptRecord.is_revealed,
      is_burned: mockReceiptRecord.is_burned,
      is_destroyed: mockReceiptRecord.is_destroyed,
      is_expired: mockReceiptRecord.is_expired,
      is_orphaned: mockReceiptRecord.is_orphaned,
      secret_ttl: mockReceiptRecord.secret_ttl,
      receipt_ttl: mockReceiptRecord.receipt_ttl,
      lifespan: mockReceiptRecord.lifespan,
      // Unix timestamps in seconds
      created: TEST_TIMESTAMPS.now,
      updated: TEST_TIMESTAMPS.now,
      expiration: TEST_TIMESTAMPS.expiration,
      // V3: nullable timestamp fields (canonical names only)
      shared: null,
      previewed: null,
      revealed: null,
      burned: null,
    };

    return {
      record: { ...baseRecord, ...overrides },
      details: mockReceiptDetails,
    };
  };

  const createBurnedMockResponse = (overrides: Record<string, unknown> = {}) => {
    const base = createMockReceiptResponse({
      key: 'burnedkey',
      state: 'burned',
      is_burned: true,
      burned: TEST_TIMESTAMPS.now,     // V3: Unix epoch seconds
      ...overrides,
    });
    return {
      ...base,
      details: mockBurnedReceiptDetails,
    };
  };

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    api = setup.api;
    appInstance = setup.appInstance;

    // Initialize the store
    store = useReceiptStore();
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('Record Creation & Update Dates', () => {
    it('properly validates created and updated dates from Unix timestamps', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockReceiptResponse({
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
      const mockResponse = createMockReceiptResponse({
        expiration: TEST_TIMESTAMPS.expiration,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.expiration).toEqual(TEST_DATES.expiration);
    });

    it('handles different Unix timestamps correctly', async () => {
      const testKey = 'testkey123';
      // Use a different timestamp for created vs updated
      const mockResponse = createMockReceiptResponse({
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

  it('handles dates correctly when fetching receipt', async () => {
    const testKey = mockReceiptRecord.key;
    const mockResponse = createMockReceiptResponse({
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

  it('handles dates correctly when burning receipt', async () => {
    const testKey = mockReceiptRecord.key; // 'testkey123'
    const mockResponse = createBurnedMockResponse({
      key: testKey,
      burned: TEST_TIMESTAMPS.now,
    });

    store.record = mockReceiptRecord;

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
    it('properly validates burned date when burning receipt (strict headers)', async () => {
      const testKey = 'testkey123';
      const mockResponse = createBurnedMockResponse({
        key: testKey,
        burned: TEST_TIMESTAMPS.now,
      });

      store.record = mockReceiptRecord;

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

    it('properly validates burned date when burning receipt (flexible)', async () => {
      const testKey = 'testkey123';
      const mockResponse = createBurnedMockResponse({
        key: testKey,
        burned: TEST_TIMESTAMPS.now,
      });

      store.record = mockReceiptRecord;

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

    it('properly fails burning receipt if it has not been requested yet', async () => {
      const testKey = 'burnedkey';
      const mockResponse = createMockReceiptResponse({
        key: testKey,
        burned: TEST_TIMESTAMPS.now,
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
        message: 'Cannot burn this receipt',
      });

      expect(store.record).toBeNull();
    });

    it('properly validates revealed date when revealing receipt', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockReceiptResponse({
        revealed: TEST_TIMESTAMPS.now, // V3 canonical (replaces received)
        state: 'revealed',             // V3 canonical (replaces received)
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.revealed).toEqual(TEST_DATES.now);
      expect(store.record?.state).toBe('revealed');
    });

    it('handles null dates for optional date fields', async () => {
      const testKey = 'testkey123';
      const mockResponse = createMockReceiptResponse({
        burned: null,
        revealed: null, // V3 canonical (replaces received)
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.burned).toBeNull();
      expect(store.record?.revealed).toBeNull();
    });
  });

  describe('Date Transformations', () => {
    it('converts Unix timestamps to Date objects', async () => {
      const testKey = 'testkey123';
      // Schema expects Unix timestamps in seconds, not milliseconds
      const mockResponse = createMockReceiptResponse({
        created: TEST_TIMESTAMPS.now,
      });

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record?.created).toEqual(TEST_DATES.now);
    });

    it('rejects invalid date formats for nullable fields (V3 expects number|null)', async () => {
      const testKey = 'testkey123';
      // Build response manually since createMockReceiptResponse enforces types
      const mockResponse = createMockReceiptResponse();
      // @ts-expect-error — intentionally passing invalid type for test
      mockResponse.record.burned = 'invalid-date';

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      // V3 toDateNullish expects number|null|undefined — string is rejected
      await expect(store.fetch(testKey)).rejects.toThrow();
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
          receipt_path: '/receipt/abc123',
          share_url: 'https://example.com/share/abc123',
          receipt_url: 'https://example.com/receipt/abc123',
          burn_url: 'https://example.com/burn/abc123',
          identifier: 'test-identifier',
          is_previewed: false,  // V3 canonical
          is_revealed: false,   // V3 canonical
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
          revealed: null,       // V3 canonical
        },
        details: mockReceiptDetails,
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
        burned: TEST_TIMESTAMPS.future,
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
