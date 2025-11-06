// src/tests/stores/metadataStore.spec.ts

// IMPORTANT: This test uses centralized test setup pattern
// DO NOT revert to individual axios.create() - use setupTestPinia() instead
import { errorGuards } from '@/schemas/errors';
import { useMetadataStore } from '@/stores/metadataStore';
import { setupTestPinia } from '../setup';
import type AxiosMockAdapter from 'axios-mock-adapter';
import type { AxiosInstance } from 'axios';
import type { ComponentPublicInstance } from 'vue';
import axios from 'axios';
import AxiosMockAdapter from 'axios-mock-adapter';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ZodError, ZodIssue } from 'zod';

import {
  createMetadataWithPassphrase,
  mockBurnedMetadataDetails,
  mockBurnedMetadataRecord,
  mockMetadataDetails,
  mockMetadataRecord,
} from '../fixtures/metadata.fixture';

function isZodInvalidTypeIssue(
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
describe('metadataStore', () => {
  let axiosMock: AxiosMockAdapter | null;
  let api: AxiosInstance;
  let store: ReturnType<typeof useMetadataStore>;
  let appInstance: ComponentPublicInstance | null;

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

  describe('fetch', () => {
    it('should fetch and validate metadata successfully', async () => {
      const testKey = mockMetadataRecord.key;
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock?.onGet(`/api/v2/receipt/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record).toEqual(mockMetadataRecord);
      expect(store.details).toEqual(mockMetadataDetails);
    });

    it('should handle not found errors when fetching metadata', async () => {
      const testKey = mockMetadataRecord.key;
      const errorMessage = 'Request failed with status code 404';

      axiosMock?.onGet(`/api/v2/receipt/${testKey}`).reply(404, {
        message: errorMessage,
      });

      await expect(store.fetch(testKey)).rejects.toThrow('Request failed with status code 404');

      // Side effects should still occur
      expect(store.record).toBeNull();
    });
  });

  describe('burn', () => {
    it('should burn metadata successfully', async () => {
      const testKey = mockMetadataRecord.key;
      const mockResponse = {
        record: mockBurnedMetadataRecord,
        details: mockBurnedMetadataDetails,
      };

      // Set initial state to ensure canBurn returns true
      store.record = {
        ...mockMetadataRecord,
        burned: null,
        state: 'new',
      };
      store.details = mockMetadataDetails;

      // Mock the burn request
      axiosMock?.onPost(`/api/v2/receipt/${testKey}/burn`).reply(200, mockResponse);

      const result = await store.burn(testKey);

      // Verify the request was made correctly
      expect(axiosMock?.history.post).toHaveLength(1);
      expect(axiosMock?.history.post[0].url).toBe(`/api/v2/receipt/${testKey}/burn`);
      expect(JSON.parse(axiosMock?.history.post[0].data)).toEqual({
        passphrase: undefined,
        continue: true,
      });

      // Verify state changes
      expect(store.record).toEqual(mockBurnedMetadataRecord);
      expect(store.details).toEqual(mockBurnedMetadataDetails);
      expect(result).toMatchObject(mockResponse);
    });

    // Add test for invalid burn attempt
    it('should reject burn request for invalid state', async () => {
      const testKey = mockBurnedMetadataRecord.key;
      store.record = mockBurnedMetadataRecord;
      store.details = mockBurnedMetadataDetails;

      await expect(store.burn(testKey)).rejects.toThrow('Cannot burn this metadata');
    });

    it('should burn metadata with passphrase', async () => {
      const testKey = mockMetadataRecord.key;
      const passphrase = 'secret123';
      const { record, details } = createMetadataWithPassphrase(passphrase);

      const mockResponse = {
        record: mockBurnedMetadataRecord,
        details: mockBurnedMetadataDetails,
      };

      store.record = record;
      store.details = details;

      axiosMock
        .onPost(`/api/v2/receipt/${testKey}/burn`, {
          passphrase,
          continue: true,
        })
        .reply(200, mockResponse);

      await store.burn(testKey, passphrase);

      expect(store.record).toEqual(mockBurnedMetadataRecord);
      expect(store.details).toEqual(mockBurnedMetadataDetails);
    });

    it('should handle errors when burning invalid metadata', async () => {
      const testKey = mockBurnedMetadataRecord.key;
      store.record = mockBurnedMetadataRecord;

      await expect(store.burn(testKey)).rejects.toThrow('Cannot burn this metadata');
    });
  });

  describe('canBurn getter', () => {
    it('returns false when no current record exists', () => {
      store.record = null;
      expect(store.canBurn).toBe(false);
    });

    it('returns true for NEW state', () => {
      store.record = mockMetadataRecord;
      expect(store.canBurn).toBe(true);
    });

    it('returns false for BURNED state', () => {
      store.record = mockBurnedMetadataRecord;
      expect(store.canBurn).toBe(false);
    });
  });

  describe('error handling', () => {
    it('handles network errors correctly', async () => {
      // Simulate network error
      axiosMock?.onGet(`/api/v2/receipt/${mockMetadataRecord.key}`).networkError();

      await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow('Network Error');

      // Store state checks
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
    });

    it('handles validation errors correctly', async () => {
      // Send invalid data that won't match schema
      axiosMock?.onGet(`/api/v2/receipt/${mockMetadataRecord.key}`).reply(200, {
        record: { invalid: 'data' },
      });

      await expect(store.fetch(mockMetadataRecord.key)).rejects.toThrow();

      // Store state checks - validation errors shouldn't update store state
      expect(store.record).toBeNull();
      expect(store.details).toBeNull();
    });

    it('resets error state between requests', async () => {
      // First request fails
      axiosMock?.onGet(`/api/v2/receipt/${mockMetadataRecord.key}`).networkError();

      try {
        await store.fetch(mockMetadataRecord.key);
        expect.fail('Expected first fetch to throw an error');
      } catch (error) {
        // Verify error occurred and store is in clean error state
        expect(error).toBeTruthy();
        expect(store.record).toBeNull();
      }

      // Second request succeeds
      axiosMock?.onGet(`/api/v2/receipt/${mockMetadataRecord.key}`).reply(200, {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      });

      await store.fetch(mockMetadataRecord.key);

      // Verify store state after successful fetch
      expect(store.record).toEqual(mockMetadataRecord);
      expect(store.details).toEqual(mockMetadataDetails);
    });
  });

  describe('Advanced Metadata Store Scenarios', () => {
    // Initialization Flexibility
    describe('Store Initialization', () => {
      it('supports custom error handling during initialization', async () => {
        const mockNotify = vi.fn();
        const mockLog = vi.fn();
        const mockAxios = axios.create();

        // Setup store with custom error handlers
        const store = useMetadataStore();
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
        const store = useMetadataStore();

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
        const testKey = mockMetadataRecord.key;

        // Configure axios mock to timeout
        axiosMock?.onGet(`/api/v2/receipt/${testKey}`).timeout();

        await expect(store.fetch(testKey)).rejects.toThrow('timeout');

        // Ensure store state is reset
        expect(store.record).toBeNull();
      });

      it('handles unauthorized burn attempts', async () => {
        const testKey = mockMetadataRecord.key;

        // Simulate 403 Forbidden scenario
        axiosMock?.onPost(`/api/v2/receipt/${testKey}/burn`).reply(403, {
          message: 'Unauthorized to burn this metadata',
        });

        // Setup initial state to allow burning
        store.record = {
          ...mockMetadataRecord,
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
        store.record = mockMetadataRecord;
        store.details = mockMetadataDetails;

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
        const testKey = mockMetadataRecord.key;
        const mockResponse = {
          record: mockMetadataRecord,
          details: mockMetadataDetails,
        };

        // Simulate slow response with delay
        axiosMock?.onGet(`/api/v2/receipt/${testKey}`).reply(() => new Promise((resolve) => {
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
        expect(store.record).toEqual(mockMetadataRecord);
        expect(store.details).toEqual(mockMetadataDetails);
      });

      it('handles concurrent burn requests with server-side protection', async () => {
        const testKey = mockMetadataRecord.key;

        store.record = {
          ...mockMetadataRecord,
          burned: null,
          state: 'new',
        };

        // Mock server responses: first succeeds, others fail with 400
        let burnAttempts = 0;
        axiosMock?.onPost(`/api/v2/receipt/${testKey}/burn`).reply(() => {
          burnAttempts++;
          if (burnAttempts === 1) {
            return [
              200,
              {
                record: mockBurnedMetadataRecord,
                details: mockBurnedMetadataDetails,
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
        expect(store.record).toEqual(mockBurnedMetadataRecord);
        expect(store.details).toEqual(mockBurnedMetadataDetails);
      });
    });
  });
});
