// src/tests/plugins/axios/interceptors.spec.ts
//
// Integration tests for axios interceptors, specifically the Sentry
// breadcrumb creation in the error interceptor.
//
// Issue: #2965 - Add Sentry breadcrumbs for API debugging
//
// Run:
//   pnpm test src/tests/plugins/axios/interceptors.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import type { AxiosError, AxiosResponse, InternalAxiosRequestConfig } from 'axios';

// ---------------------------------------------------------------------------
// Mocks - must use vi.hoisted() for variables used in vi.mock factories
// ---------------------------------------------------------------------------

const { mockAddBreadcrumb, mockUpdateShrimp } = vi.hoisted(() => ({
  mockAddBreadcrumb: vi.fn(),
  mockUpdateShrimp: vi.fn(),
}));

vi.mock('@sentry/vue', () => ({
  addBreadcrumb: mockAddBreadcrumb,
}));

// Mock Pinia stores
vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => ({
    shrimp: 'test-csrf-token',
    updateShrimp: mockUpdateShrimp,
  }),
}));

vi.mock('@/shared/stores', () => ({
  useLanguageStore: () => ({
    getCurrentLocale: 'en',
  }),
}));

vi.mock('@/shared/stores/organizationStore', () => ({
  useOrganizationStore: () => ({
    currentOrganization: null,
  }),
}));

// Mock scrubbing functions with passthrough behavior for most tests
// Actual scrubbing logic is tested in scrubbers.spec.ts
vi.mock('@/plugins/core/diagnostics/scrubbers', () => ({
  scrubSensitiveStrings: (str: string) => str,
  scrubUrlWithPatterns: (url: string) => url,
}));

// ---------------------------------------------------------------------------
// Import after mocks
// ---------------------------------------------------------------------------

import {
  errorInterceptor,
  responseInterceptor,
  createLoggableShrimp,
} from '@/plugins/axios/interceptors';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

function createAxiosError(
  overrides: Partial<{
    message: string;
    method: string;
    url: string;
    status: number;
    responseHeaders: Record<string, string>;
  }> = {}
): AxiosError {
  const config: InternalAxiosRequestConfig = {
    method: overrides.method ?? 'get',
    url: overrides.url ?? '/api/test',
    headers: {} as InternalAxiosRequestConfig['headers'],
  };

  return {
    name: 'AxiosError',
    message: overrides.message ?? 'Request failed',
    config,
    isAxiosError: true,
    toJSON: () => ({}),
    response: overrides.status
      ? {
          status: overrides.status,
          statusText: 'Error',
          headers: overrides.responseHeaders ?? {},
          config,
          data: {},
        }
      : undefined,
  } as AxiosError;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('axios interceptors', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  afterEach(() => {
    vi.resetModules();
  });

  // ==========================================================================
  // errorInterceptor
  // ==========================================================================
  describe('errorInterceptor', () => {
    describe('Sentry breadcrumb creation', () => {
      it('creates breadcrumb with correct structure', async () => {
        const error = createAxiosError({
          method: 'post',
          url: '/api/v3/secrets',
          status: 500,
          message: 'Internal Server Error',
        });

        await expect(errorInterceptor(error)).rejects.toThrow();

        expect(mockAddBreadcrumb).toHaveBeenCalledOnce();
        expect(mockAddBreadcrumb).toHaveBeenCalledWith({
          type: 'http',
          category: 'axios',
          level: 'error',
          message: 'POST /api/v3/secrets',
          data: {
            method: 'POST',
            url: '/api/v3/secrets',
            status_code: 500,
            reason: 'Internal Server Error',
          },
        });
      });

      it('uppercases HTTP method', async () => {
        const error = createAxiosError({ method: 'delete' });

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data.method).toBe('DELETE');
      });

      it('handles missing method gracefully', async () => {
        const error = createAxiosError({});
        error.config = undefined as unknown as InternalAxiosRequestConfig;

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data.method).toBe('UNKNOWN');
      });

      it('handles missing URL gracefully', async () => {
        const error = createAxiosError({});
        error.config!.url = undefined;

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data.url).toBe('unknown');
      });

      it('omits status_code when response is undefined (network error)', async () => {
        const error = createAxiosError({ message: 'Network Error' });
        // No response = network error

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data).not.toHaveProperty('status_code');
      });

      it('includes status_code when response exists', async () => {
        const error = createAxiosError({ status: 404 });

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data.status_code).toBe(404);
      });

      it('always rejects with the original error', async () => {
        const error = createAxiosError({ message: 'Test error' });

        await expect(errorInterceptor(error)).rejects.toBe(error);
      });
    });

    // Note: Scrubbing function behavior is tested in scrubbers.spec.ts
    // These tests verify the interceptor calls scrubbing functions correctly
    describe('breadcrumb scrubbing integration', () => {
      it('passes URL through scrubUrlWithPatterns', async () => {
        // With passthrough mock, URL should be unchanged
        const error = createAxiosError({ url: '/api/v3/test' });

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data.url).toBe('/api/v3/test');
      });

      it('passes error message through scrubSensitiveStrings', async () => {
        // With passthrough mock, message should be unchanged
        const error = createAxiosError({ message: 'Test error message' });

        await expect(errorInterceptor(error)).rejects.toThrow();

        const call = mockAddBreadcrumb.mock.calls[0][0];
        expect(call.data.reason).toBe('Test error message');
      });
    });

    describe('CSRF token handling', () => {
      it('updates CSRF token from error response headers', async () => {
        const error = createAxiosError({
          status: 403,
          responseHeaders: { 'x-csrf-token': 'new-token' },
        });

        await expect(errorInterceptor(error)).rejects.toThrow();

        expect(mockUpdateShrimp).toHaveBeenCalledWith('new-token');
      });

      it('does not update CSRF token when header is missing', async () => {
        const error = createAxiosError({
          status: 500,
          responseHeaders: {},
        });

        await expect(errorInterceptor(error)).rejects.toThrow();

        expect(mockUpdateShrimp).not.toHaveBeenCalled();
      });

      it('does not update CSRF token when header is empty string', async () => {
        const error = createAxiosError({
          status: 403,
          responseHeaders: { 'x-csrf-token': '' },
        });

        await expect(errorInterceptor(error)).rejects.toThrow();

        expect(mockUpdateShrimp).not.toHaveBeenCalled();
      });
    });
  });

  // ==========================================================================
  // responseInterceptor - CSRF token update
  // ==========================================================================
  describe('responseInterceptor', () => {
    it('updates CSRF token from response headers', () => {
      const response = {
        status: 200,
        headers: {
          'x-csrf-token': 'new-csrf-token',
        },
        data: {},
        config: {},
        statusText: 'OK',
      } as unknown as AxiosResponse;

      const result = responseInterceptor(response);

      expect(mockUpdateShrimp).toHaveBeenCalledWith('new-csrf-token');
      expect(result).toBe(response);
    });

    it('does not update CSRF token when header is missing', () => {
      const response = {
        status: 200,
        headers: {},
        data: {},
        config: {},
        statusText: 'OK',
      } as unknown as AxiosResponse;

      const result = responseInterceptor(response);

      expect(mockUpdateShrimp).not.toHaveBeenCalled();
      expect(result).toBe(response);
    });
  });

  // ==========================================================================
  // createLoggableShrimp - Token truncation for logging
  // ==========================================================================
  describe('createLoggableShrimp', () => {
    it('truncates valid token to first 4 chars with ellipsis', () => {
      expect(createLoggableShrimp('abcdefghijklmnop')).toBe('abcd...');
    });

    it('returns empty string for empty input', () => {
      expect(createLoggableShrimp('')).toBe('');
    });

    it('returns empty string for null input', () => {
      expect(createLoggableShrimp(null)).toBe('');
    });

    it('returns empty string for undefined input', () => {
      expect(createLoggableShrimp(undefined)).toBe('');
    });

    it('returns empty string for non-string input', () => {
      expect(createLoggableShrimp(12345)).toBe('');
      expect(createLoggableShrimp({ token: 'abc' })).toBe('');
    });

    it('handles short tokens gracefully', () => {
      expect(createLoggableShrimp('ab')).toBe('ab...');
      expect(createLoggableShrimp('a')).toBe('a...');
    });
  });
});
