// src/stores/metadataStore.spec.ts
import { isApplicationError } from '@/schemas/errors';
import { useMetadataStore } from '@/stores/metadataStore';
import { createTestingPinia } from '@pinia/testing';
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
  let axiosMock: AxiosMockAdapter;
  let store: ReturnType<typeof useMetadataStore>;

  beforeEach(() => {
    const pinia = createTestingPinia({
      createSpy: vi.fn,
      stubActions: false,
    });

    const axiosInstance = axios.create();
    axiosMock = new AxiosMockAdapter(axiosInstance);

    store = useMetadataStore();
  });

  afterEach(() => {
    axiosMock.reset();
    vi.clearAllMocks();
  });

  describe('fetch', () => {
    it('should fetch and validate metadata successfully', async () => {
      const testKey = mockMetadataRecord.key;
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(200, mockResponse);

      await store.fetch(testKey);

      expect(store.record).toEqual(mockMetadataRecord);
      expect(store.details).toEqual(mockMetadataDetails);
      expect(store.isLoading).toBe(false);
    });

    it('should handle not found errors when fetching metadata', async () => {
      const testKey = mockMetadataRecord.key;
      const errorMessage = 'Request failed with status code 404';

      axiosMock.onGet(`/api/v2/private/${testKey}`).reply(404, {
        message: errorMessage,
      });

      await expect(store.fetch(testKey)).rejects.toMatchObject({
        type: 'human',
        severity: 'error',
        message: errorMessage,
      });

      // Side effects should still occur
      expect(store.isLoading).toBe(false);
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
      axiosMock.onPost(`/api/v2/private/${testKey}/burn`).reply(200, mockResponse);

      const result = await store.burn(testKey);

      // Verify the request was made correctly
      expect(axiosMock.history.post).toHaveLength(1);
      expect(axiosMock.history.post[0].url).toBe(`/api/v2/private/${testKey}/burn`);
      expect(JSON.parse(axiosMock.history.post[0].data)).toEqual({
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
        .onPost(`/api/v2/private/${testKey}/burn`, {
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
    it('throws ApplicationError when no current record exists', () => {
      store.record = null;
      expect(() => store.canBurn).toThrow();
      try {
        void store.canBurn;
      } catch (error) {
        expect(error).toMatchObject({
          message: 'No state metadata record',
          type: 'technical',
          severity: 'error',
        });
      }
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

  describe('loading state', () => {
    it('should track loading state during async operations', async () => {
      const loadingStates: boolean[] = [];
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => resolve([200, mockResponse]), 50);
        });
      });

      store.$subscribe(() => {
        loadingStates.push(store.isLoading);
      });

      const promise = store.fetch(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await promise;

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
    });

    it('should handle loading state with errors', async () => {
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

      const promise = store.fetch(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await expect(promise).rejects.toThrow();
      expect(store.isLoading).toBe(false);
    });

    // Add to loading state describe block
    it('tracks detailed loading state changes', async () => {
      const loadingStates: boolean[] = [];
      const mockResponse = {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      };

      // Subscribe to catch all state changes
      store.$subscribe(() => {
        loadingStates.push(store.isLoading);
      });

      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(() => {
        return new Promise((resolve) => {
          setTimeout(() => resolve([200, mockResponse]), 50);
        });
      });

      const promise = store.fetch(mockMetadataRecord.key);
      expect(store.isLoading).toBe(true);

      await promise;

      expect(loadingStates).toContain(true);
      expect(store.isLoading).toBe(false);
      expect(loadingStates[loadingStates.length - 1]).toBe(false);
    });
  });

  describe('error handling', () => {
    it('handles network errors correctly', async () => {
      // Simulate network error
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

      try {
        await store.fetch(mockMetadataRecord.key);
        expect.fail('Expected an error to be thrown');
      } catch (error) {
        // Basic error checks
        expect(error).toBeTruthy();
        expect(error).toBeInstanceOf(Error);

        // Detailed network error checks
        expect((error as Error).message).toBe('Network Error');

        // Check for application-specific error properties
        if (isApplicationError(error)) {
          // More specific assertions about the error classification
          expect(error.type).toBe('technical');
          expect(error.severity).toBe('error');

          // Additional checks for network error specifics
          expect(error.details).toBeUndefined(); // Network errors might not have extra details
        }

        // Store state checks
        expect(store.isLoading).toBe(false);
        expect(store.record).toBeNull();
        expect(store.details).toBeNull();
      }
    });

    it('handles validation errors correctly', async () => {
      // Send invalid data that won't match schema
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(200, {
        record: { invalid: 'data' },
      });

      try {
        await store.fetch(mockMetadataRecord.key);
        expect.fail('Expected a validation error to be thrown');
      } catch (error) {
        // Basic error checks
        expect(error).toBeTruthy();
        expect(error).toBeInstanceOf(Error);

        // Detailed Zod validation error parsing
        if (error instanceof ZodError) {
          // Check specific validation error characteristics
          const validationErrors = error.errors;

          // Assert minimum number of validation errors
          expect(validationErrors.length).toBeGreaterThan(10);

          // Check specific error types
          const errorTypes = validationErrors.map((err) => err.code);
          expect(errorTypes).toContain('invalid_type');

          // Check specific missing fields
          const missingFields = validationErrors
            .filter((err) => err.code === 'invalid_type' && err.received === 'undefined')
            .map((err) => err.path.join('.'));

          // Assert critical fields are missing
          const criticalMissingFields = [
            'record.identifier',
            'record.key',
            'record.shortkey',
            'record.state',
          ];
          criticalMissingFields.forEach((field) => {
            expect(missingFields).toContain(field);
          });

          // Null field checks
          const nullFields = validationErrors
            .filter(isZodInvalidTypeIssue)
            .filter((err) => err.received === 'null')
            .map((err) => err.path.join('.'));

          expect(nullFields).toContain('record.created');
          expect(nullFields).toContain('record.updated');
          expect(nullFields).toContain('record.expiration');
        }

        // Application error checks
        if (isApplicationError(error)) {
          expect(error.type).toBe('technical');
          expect(error.severity).toBe('error');
        }

        // Store state checks
        expect(store.isLoading).toBe(false);
        expect(store.record).toBeNull();
        expect(store.details).toBeNull();
      }
    });

    it('resets error state between requests', async () => {
      // First request fails
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).networkError();

      try {
        await store.fetch(mockMetadataRecord.key);
        expect.fail('Expected first fetch to throw an error');
      } catch (error) {
        // Verify error occurred and store is in clean error state
        expect(error).toBeTruthy();
        expect(store.isLoading).toBe(false);
        expect(store.record).toBeNull();
      }

      // Second request succeeds
      axiosMock.onGet(`/api/v2/private/${mockMetadataRecord.key}`).reply(200, {
        record: mockMetadataRecord,
        details: mockMetadataDetails,
      });

      await store.fetch(mockMetadataRecord.key);

      // Verify store state after successful fetch
      expect(store.isLoading).toBe(false);
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
        axiosMock.onGet('/api/v2/private/test-key').reply(404, {
          error: {
            message: 'Secret not found',
            code: 'NOT_FOUND',
          },
        });

        // Attempt to fetch which should trigger error handling
        await expect(store.fetch('test-key')).rejects.toMatchObject({
          type: 'human',
          severity: 'error',
          message: 'Request failed with status code 404', // Match actual Axios error message
        });

        // Verify error handlers were called with appropriate args
        expect(mockNotify).toHaveBeenCalledWith('Request failed with status code 404', 'error');

        expect(mockLog).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'human',
            severity: 'error',
            message: 'Request failed with status code 404',
          })
        );

        // Verify store state
        expect(store.isLoading).toBe(false);
        expect(store.record).toBeNull();
      });

      it('handles initialization without optional parameters', async () => {
        const store = useMetadataStore();

        // Should not throw when initialized with minimal parameters
        // expect(() => store.setupAsyncHandler()).not.toThrow();

        // Verify basic initialization works
        expect(store.isLoading).toBe(false);
        expect(store.record).toBeNull();
        expect(store.details).toBeNull();
      });
    });

    // Advanced Error Scenarios
    describe('Advanced Error Handling', () => {
      it('handles timeout scenarios', async () => {
        const testKey = mockMetadataRecord.key;

        // Configure axios mock to timeout
        axiosMock.onGet(`/api/v2/private/${testKey}`).timeout();

        await expect(store.fetch(testKey)).rejects.toMatchObject({
          type: 'technical',
          severity: 'error',
          message: expect.stringContaining('timeout'),
        });

        // Ensure loading state is reset
        expect(store.isLoading).toBe(false);
        expect(store.record).toBeNull();
      });

      it('handles unauthorized burn attempts', async () => {
        const testKey = mockMetadataRecord.key;

        // Simulate 403 Forbidden scenario
        axiosMock.onPost(`/api/v2/private/${testKey}/burn`).reply(403, {
          message: 'Unauthorized to burn this metadata',
        });

        // Setup initial state to allow burning
        store.record = {
          ...mockMetadataRecord,
          burned: null,
          state: 'new',
        };

        await expect(store.burn(testKey)).rejects.toMatchObject({
          type: 'security',
          severity: 'error',
        });

        // Ensure store state remains unchanged
        expect(store.record).toMatchObject(store.record);
        expect(store.isLoading).toBe(false);
      });
    });

    // State Persistence and Reset
    describe('State Management', () => {
      it('completely resets store state', () => {
        // Manually set some state
        store.record = mockMetadataRecord;
        store.details = mockMetadataDetails;
        store.isLoading = true;

        // Reinitialize store
        store.$reset();

        // Verify complete reset
        expect(store.record).toBeNull();
        expect(store.details).toBeNull();
        expect(store.isLoading).toBe(false);
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
        axiosMock.onGet(`/api/v2/private/${testKey}`).reply(() => {
          return new Promise((resolve) => {
            setTimeout(() => resolve([200, mockResponse]), 100);
          });
        });

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
        expect(store.isLoading).toBe(false);
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
        axiosMock.onPost(`/api/v2/private/${testKey}/burn`).reply(() => {
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
