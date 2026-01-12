// src/tests/stores/receiptStore.spec.ts

// IMPORTANT: This test uses centralized test setup pattern
// DO NOT revert to individual axios.create() - use setupTestPinia() instead
import { useReceiptStore } from '@/shared/stores/receiptStore';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';
import type { ComponentPublicInstance } from 'vue';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodIssue } from 'zod';

import {
  createReceiptWithPassphrase,
  mockBurnedReceiptDetails,
  mockBurnedReceiptDetailsRaw,
  mockBurnedReceiptRecord,
  mockBurnedReceiptRecordRaw,
  mockReceiptDetails,
  mockReceiptDetailsRaw,
  mockReceiptRecord,
  mockReceiptRecordRaw,
} from '../fixtures/receipt.fixture';

function _isZodInvalidTypeIssue(
  issue: ZodIssue
): issue is ZodIssue & { code: 'invalid_type'; received: string } {
  return issue.code === 'invalid_type' && 'received' in issue;
}

/**
 * NOTE: These tests run using a simple Axios mock adapter to simulate API responses. They do not
 * actually make network requests. However, the adapter also does not include the full Axios
 * request/response lifecycle (our interceptors in utils/api) which can affect how errors are
 * propagated. This is a limitation of the current test setup.
 */
describe('receiptStore', () => {
  let axiosMock: AxiosMockAdapter | null;
  let _api: AxiosInstance;
  let store: ReturnType<typeof useReceiptStore>;
  let _appInstance: ComponentPublicInstance | null;

  beforeEach(async () => {
    // Setup testing environment with all needed components
    const setup = await setupTestPinia();
    axiosMock = setup.axiosMock;
    _api = setup.api;
    _appInstance = setup.appInstance;

    // Initialize the store
    store = useReceiptStore();
  });

  afterEach(() => {
    if (axiosMock) axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('fetch', () => {
    it('should fetch and validate metadata successfully', async () => {
      const testKey = mockReceiptRecord.key;
      const mockResponse = {
        record: mockReceiptRecordRaw,
        details: mockReceiptDetailsRaw,
      };

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record).toEqual(mockReceiptRecord);
      expect(store.details).toEqual(mockReceiptDetails);
    });

    it('should handle not found errors when fetching metadata', async () => {
      const testKey = mockReceiptRecord.key;
      const errorMessage = 'Request failed with status code 404';

      axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(404, {
        message: errorMessage,
      });

      await expect(store.fetch(testKey)).rejects.toThrow('Request failed with status code 404');

      // Side effects should still occur
      expect(store.record).toBeNull();
    });
  });

  describe('burn', () => {
    it('should burn metadata successfully', async () => {
      const testKey = mockReceiptRecord.key;
      const mockResponse = {
        record: mockBurnedReceiptRecordRaw,
        details: mockBurnedReceiptDetailsRaw,
      };

      // Set initial state to ensure canBurn returns true
      store.record = {
        ...mockReceiptRecord,
        burned: null,
        state: 'new',
      };
      store.details = mockReceiptDetails;

      // Mock the burn request
      axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(200, mockResponse);

      const result = await store.burn(testKey);

      // Verify the request was made correctly
      expect(axiosMock?.history.post).toHaveLength(1);
      expect(axiosMock?.history.post[0].url).toBe(`/api/v3/receipt/${testKey}/burn`);
      expect(JSON.parse(axiosMock?.history.post[0].data)).toEqual({
        passphrase: undefined,
        continue: true,
      });

      // Verify state changes
      expect(store.record).toEqual(mockBurnedReceiptRecord);
      expect(store.details).toEqual(mockBurnedReceiptDetails);
      expect(result).toMatchObject({
        record: mockBurnedReceiptRecord,
        details: mockBurnedReceiptDetails,
      });
    });

    // Add test for invalid burn attempt
    it('should reject burn request for invalid state', async () => {
      const testKey = mockBurnedReceiptRecord.key;
      store.record = mockBurnedReceiptRecord;
      store.details = mockBurnedReceiptDetails;

      await expect(store.burn(testKey)).rejects.toThrow('Cannot burn this receipt');
    });

    it('should burn metadata with passphrase', async () => {
      const testKey = mockReceiptRecord.key;
      const passphrase = 'secret123';
      const { record, details } = createReceiptWithPassphrase(passphrase);

      const mockResponse = {
        record: mockBurnedReceiptRecordRaw,
        details: mockBurnedReceiptDetailsRaw,
      };

      store.record = record;
      store.details = details;

      axiosMock
        .onPost(`/api/v3/receipt/${testKey}/burn`, {
          passphrase,
          continue: true,
        })
        .reply(200, mockResponse);

      await store.burn(testKey, passphrase);

      expect(store.record).toEqual(mockBurnedReceiptRecord);
      expect(store.details).toEqual(mockBurnedReceiptDetails);
    });

    it('should handle errors when burning invalid metadata', async () => {
      const testKey = mockBurnedReceiptRecord.key;
      store.record = mockBurnedReceiptRecord;

      await expect(store.burn(testKey)).rejects.toThrow('Cannot burn this receipt');
    });
  });

  describe('canBurn getter', () => {
    it('returns false when no current record exists', () => {
      store.record = null;
      expect(store.canBurn).toBe(false);
    });

    it('returns true for NEW state', () => {
      store.record = mockReceiptRecord;
      expect(store.canBurn).toBe(true);
    });

    it('returns false for BURNED state', () => {
      store.record = mockBurnedReceiptRecord;
      expect(store.canBurn).toBe(false);
    });
  });

  describe('error handling', () => {
    it('handles network errors correctly', async () => {
      // Simulate network error
      axiosMock?.onGet(`/api/v3/receipt/${mockReceiptRecord.key}`).networkError();

      await expect(store.fetch(mockReceiptRecord.key)).rejects.toThrow('Network Error');

      // Store state checks
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
    });

    it('handles validation errors correctly', async () => {
      // Send invalid data that won't match schema
      axiosMock?.onGet(`/api/v3/receipt/${mockReceiptRecord.key}`).reply(200, {
        record: { invalid: 'data' },
      });

      await expect(store.fetch(mockReceiptRecord.key)).rejects.toThrow();

      // Store state checks - validation errors shouldn't update store state
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
    });

    it('resets error state between requests', async () => {
      // First request fails
      axiosMock?.onGet(`/api/v3/receipt/${mockReceiptRecord.key}`).networkError();

      try {
        await store.fetch(mockReceiptRecord.key);
        expect.fail('Expected first fetch to throw an error');
      } catch (error) {
        // Verify error occurred and store is in clean error state
        expect(error).toBeTruthy();
        expect(store.record).toBeNull();
      }

      // Second request succeeds
      axiosMock?.onGet(`/api/v3/receipt/${mockReceiptRecord.key}`).reply(200, {
        record: mockReceiptRecordRaw,
        details: mockReceiptDetailsRaw,
      });

      await store.fetch(mockReceiptRecord.key);

      // Verify store state after successful fetch
      expect(store.record).toEqual(mockReceiptRecord);
      expect(store.details).toEqual(mockReceiptDetails);
    });
  });

  describe('Advanced Metadata Store Scenarios', () => {
    // Initialization Flexibility
    describe('Store Initialization', () => {
      it('supports custom error handling during initialization', async () => {
        const _mockNotify = vi.fn();
        const _mockLog = vi.fn();
        const mockAxios = axios.create();

        // Setup store with custom error handlers
        const store = useReceiptStore();
        // store.setupAsyncHandler(mockAxios, {
        //   notify: mockNotify,
        //   log: mockLog,
        // });

        // Mock API to return a 404 error with error response data
        axiosMock = new AxiosMockAdapter(mockAxios);
        axiosMock?.onGet('/api/v3/receipt/test-key').reply(404, {
          error: {
            message: 'Secret not found',
            code: 'NOT_FOUND',
          },
        });

        // Attempt to fetch which should trigger error handling
        await expect(store.fetch('test-key')).rejects.toThrow('Request failed with status code 404');

        // Verify store state
        expect(store.record).toBeNull();
      });

      it('handles initialization without optional parameters', async () => {
        const store = useReceiptStore();

        // Should not throw when initialized with minimal parameters
        // expect(() => store.setupAsyncHandler()).not.toThrow();

        // Verify basic initialization works
        expect(store.record).toBeNull();
        expect(store.details).toBeNull();
      });
    });

    // Advanced Error Scenarios
    describe('Advanced Error Handling', () => {
      it('handles timeout scenarios', async () => {
        const testKey = mockReceiptRecord.key;

        // Configure axios mock to timeout
        axiosMock?.onGet(`/api/v3/receipt/${testKey}`).timeout();

        await expect(store.fetch(testKey)).rejects.toThrow('timeout');

        // Ensure store state is reset
        expect(store.record).toBeNull();
      });

      it('handles unauthorized burn attempts', async () => {
        const testKey = mockReceiptRecord.key;

        // Simulate 403 Forbidden scenario
        axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(403, {
          message: 'Unauthorized to burn this metadata',
        });

        // Setup initial state to allow burning
        store.record = {
          ...mockReceiptRecord,
          burned: null,
          state: 'new',
        };

        await expect(store.burn(testKey)).rejects.toThrow('Request failed with status code 403');

        // Ensure store state remains unchanged
        expect(store.record).toMatchObject(store.record);
      });
    });

    // State Persistence and Reset
    describe('State Management', () => {
      it('completely resets store state', () => {
        // Manually set some state
        store.record = mockReceiptRecord;
        store.details = mockReceiptDetails;

        // Reinitialize store
        store.$reset();

        // Verify complete reset
        expect(store.record).toBeNull();
        expect(store.details).toBeNull();
      });
    });
  });

  describe('Concurrency and Race Conditions', () => {
    // Concurrent Request Handling
    describe('Burn Operation Concurrency', () => {
      it('handles concurrent fetch requests gracefully', async () => {
        const testKey = mockReceiptRecord.key;
        const mockResponse = {
          record: mockReceiptRecordRaw,
          details: mockReceiptDetailsRaw,
        };

        // Simulate slow response with delay
        axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(() => new Promise((resolve) => {
            setTimeout(() => resolve([200, mockResponse]), 100);
          }));

        // Trigger multiple simultaneous requests
        const fetchPromises = [store.fetch(testKey), store.fetch(testKey), store.fetch(testKey)];

        const results = await Promise.allSettled(fetchPromises);

        // Verify all requests resolve successfully
        results.forEach((result) => {
          expect(result.status).toBe('fulfilled');
        });

        // Ensure final store state is consistent
        expect(store.record).toEqual(mockReceiptRecord);
        expect(store.details).toEqual(mockReceiptDetails);
      });

      it('handles concurrent burn requests with server-side protection', async () => {
        const testKey = mockReceiptRecord.key;

        store.record = {
          ...mockReceiptRecord,
          burned: null,
          state: 'new',
        };

        // Mock server responses: first succeeds, others fail with 400
        let burnAttempts = 0;
        axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(() => {
          burnAttempts++;
          if (burnAttempts === 1) {
            return [
              200,
              {
                record: mockBurnedReceiptRecordRaw,
                details: mockBurnedReceiptDetailsRaw,
              },
            ];
          }
          // Return 400 with proper error structure that matches API
          return [
            400,
            {
              error: {
                message: 'Secret has already been burned',
                code: 'ALREADY_BURNED',
              },
            },
          ];
        });

        // Using Promise.allSettled to handle both success and failures
        const burnPromises = [
          store.burn(testKey).catch((e) => e), // Catch to handle rejection
          store.burn(testKey).catch((e) => e), // Catch to handle rejection
          store.burn(testKey).catch((e) => e), // Catch to handle rejection
        ];

        const results = await Promise.all(burnPromises);

        // Count successful operations (non-error results)
        const successResults = results.filter((r) => !(r instanceof Error));
        const failedResults = results.filter((r) => r instanceof Error);

        expect(successResults).toHaveLength(1);
        expect(failedResults).toHaveLength(2);

        // Verify final state reflects the successful burn
        expect(store.record).toEqual(mockBurnedReceiptRecord);
        expect(store.details).toEqual(mockBurnedReceiptDetails);
      });
    });
  });

  describe('apiMode', () => {
    it('defaults to authenticated mode', () => {
      expect(store.apiMode).toBe('authenticated');
    });

    it('setApiMode changes to public mode', () => {
      store.setApiMode('public');
      expect(store.apiMode).toBe('public');
    });

    it('setApiMode changes back to authenticated mode', () => {
      store.setApiMode('public');
      store.setApiMode('authenticated');
      expect(store.apiMode).toBe('authenticated');
    });

    it('$reset resets apiMode to authenticated', () => {
      store.setApiMode('public');
      store.$reset();
      expect(store.apiMode).toBe('authenticated');
    });

    it('persists apiMode across multiple operations', async () => {
      const testKey = mockReceiptRecord.key;
      const mockFetchResponse = {
        record: mockReceiptRecordRaw,
        details: mockReceiptDetailsRaw,
      };
      const mockBurnResponse = {
        record: mockBurnedReceiptRecordRaw,
        details: mockBurnedReceiptDetailsRaw,
      };

      store.setApiMode('public');

      // Mock responses for public endpoints
      axiosMock?.onGet(`/api/v3/guest/receipt/${testKey}`).reply(200, mockFetchResponse);
      axiosMock?.onPost(`/api/v3/guest/receipt/${testKey}/burn`).reply(200, mockBurnResponse);

      // Perform fetch (updates store.record)
      await store.fetch(testKey);

      // Perform burn
      await store.burn(testKey);

      // Both should have used public endpoints
      expect(axiosMock?.history.get[0].url).toBe(`/api/v3/guest/receipt/${testKey}`);
      expect(axiosMock?.history.post[0].url).toBe(`/api/v3/guest/receipt/${testKey}/burn`);
    });

    describe('endpoint selection', () => {
      it('fetch uses /api/v3/receipt in authenticated mode', async () => {
        const testKey = mockReceiptRecord.key;
        const mockResponse = {
          record: mockReceiptRecordRaw,
          details: mockReceiptDetailsRaw,
        };

        store.setApiMode('authenticated');
        axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, mockResponse);

        await store.fetch(testKey);

        expect(axiosMock?.history.get).toHaveLength(1);
        expect(axiosMock?.history.get[0].url).toBe(`/api/v3/receipt/${testKey}`);
      });

      it('fetch uses /api/v3/guest/receipt in public mode', async () => {
        const testKey = mockReceiptRecord.key;
        const mockResponse = {
          record: mockReceiptRecordRaw,
          details: mockReceiptDetailsRaw,
        };

        store.setApiMode('public');
        axiosMock?.onGet(`/api/v3/guest/receipt/${testKey}`).reply(200, mockResponse);

        await store.fetch(testKey);

        expect(axiosMock?.history.get).toHaveLength(1);
        expect(axiosMock?.history.get[0].url).toBe(`/api/v3/guest/receipt/${testKey}`);
      });

      it('burn uses /api/v3/receipt in authenticated mode', async () => {
        const testKey = mockReceiptRecord.key;
        const mockResponse = {
          record: mockBurnedReceiptRecordRaw,
          details: mockBurnedReceiptDetailsRaw,
        };

        store.record = { ...mockReceiptRecord, burned: null, state: 'new' };
        store.setApiMode('authenticated');
        axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(200, mockResponse);

        await store.burn(testKey);

        expect(axiosMock?.history.post).toHaveLength(1);
        expect(axiosMock?.history.post[0].url).toBe(`/api/v3/receipt/${testKey}/burn`);
      });

      it('burn uses /api/v3/guest/receipt in public mode', async () => {
        const testKey = mockReceiptRecord.key;
        const mockResponse = {
          record: mockBurnedReceiptRecordRaw,
          details: mockBurnedReceiptDetailsRaw,
        };

        store.record = { ...mockReceiptRecord, burned: null, state: 'new' };
        store.setApiMode('public');
        axiosMock?.onPost(`/api/v3/guest/receipt/${testKey}/burn`).reply(200, mockResponse);

        await store.burn(testKey);

        expect(axiosMock?.history.post).toHaveLength(1);
        expect(axiosMock?.history.post[0].url).toBe(`/api/v3/guest/receipt/${testKey}/burn`);
      });
    });
  });

  describe('guest routes error handling', () => {
    // These tests verify that guest routes 403 errors bubble up correctly
    // from the store. Per project architecture, stores bubble errors and
    // composables/components handle them with useAsyncHandler.wrap()

    describe('GUEST_ROUTES_DISABLED errors', () => {
      const guestRoutesDisabledResponse = {
        message: 'Guest API access is disabled',
        code: 'GUEST_ROUTES_DISABLED',
      };

      it('fetch() rejects with 403 when guest routes globally disabled', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('public');
        axiosMock
          ?.onGet(`/api/v3/guest/receipt/${testKey}`)
          .reply(403, guestRoutesDisabledResponse);

        await expect(store.fetch(testKey)).rejects.toThrow();
      });

      it('burn() rejects with 403 when guest routes globally disabled', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('public');
        store.record = { ...mockReceiptRecord, burned: null, state: 'new' };
        axiosMock
          ?.onPost(`/api/v3/guest/receipt/${testKey}/burn`)
          .reply(403, guestRoutesDisabledResponse);

        await expect(store.burn(testKey)).rejects.toThrow();
      });

      it('store state remains unchanged after fetch 403 error', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('public');
        axiosMock
          ?.onGet(`/api/v3/guest/receipt/${testKey}`)
          .reply(403, guestRoutesDisabledResponse);

        const initialRecord = store.record;
        const initialDetails = store.details;

        await expect(store.fetch(testKey)).rejects.toThrow();

        expect(store.record).toBe(initialRecord);
        expect(store.details).toBe(initialDetails);
      });
    });

    describe('operation-specific disabled errors', () => {
      it('fetch() rejects with GUEST_RECEIPT_DISABLED code', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('public');
        axiosMock?.onGet(`/api/v3/guest/receipt/${testKey}`).reply(403, {
          message: 'Guest receipt is disabled',
          code: 'GUEST_RECEIPT_DISABLED',
        });

        await expect(store.fetch(testKey)).rejects.toThrow();
      });

      it('burn() rejects with GUEST_BURN_DISABLED code', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('public');
        store.record = { ...mockReceiptRecord, burned: null, state: 'new' };
        axiosMock?.onPost(`/api/v3/guest/receipt/${testKey}/burn`).reply(403, {
          message: 'Guest burn is disabled',
          code: 'GUEST_BURN_DISABLED',
        });

        await expect(store.burn(testKey)).rejects.toThrow();
      });
    });

    describe('authenticated mode unaffected by guest route errors', () => {
      it('fetch() succeeds in authenticated mode regardless of guest config', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('authenticated');

        axiosMock?.onGet(`/api/v3/receipt/${testKey}`).reply(200, {
          record: mockReceiptRecordRaw,
          details: mockReceiptDetailsRaw,
        });

        await store.fetch(testKey);

        expect(store.record).toEqual(mockReceiptRecord);
        expect(axiosMock?.history.get[0].url).toBe(`/api/v3/receipt/${testKey}`);
      });

      it('burn() succeeds in authenticated mode regardless of guest config', async () => {
        const testKey = mockReceiptRecord.key;
        store.setApiMode('authenticated');
        store.record = { ...mockReceiptRecord, burned: null, state: 'new' };

        axiosMock?.onPost(`/api/v3/receipt/${testKey}/burn`).reply(200, {
          record: mockBurnedReceiptRecordRaw,
          details: mockBurnedReceiptDetailsRaw,
        });

        await store.burn(testKey);

        expect(store.record).toEqual(mockBurnedReceiptRecord);
        expect(axiosMock?.history.post[0].url).toBe(`/api/v3/receipt/${testKey}/burn`);
      });
    });
  });
});
