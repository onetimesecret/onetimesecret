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
  requestInterceptor,
  responseInterceptor,
  createLoggableShrimp,
  resetApiRouteSlotLifecycle,
} from '@/plugins/axios/interceptors';
import { resetApiRouteContext, resolveApiRoute } from '@/utils/telemetry/apiRouteContext';

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
  // requestInterceptor -> parameterized API-route context (requirement 6)
  //
  // `setCurrentApiRoute` has exactly ONE production caller, and it is this
  // interceptor. Without it `resolveApiRoute()` returns undefined forever and
  // the whole route-context feature ships inert, which is precisely the state
  // these tests exist to prevent from recurring.
  // ==========================================================================
  describe('requestInterceptor api-route context', () => {
    beforeEach(() => {
      resetApiRouteContext();
    });

    afterEach(() => {
      resetApiRouteContext();
    });

    function configFor(url: string | undefined): InternalAxiosRequestConfig {
      return { url, headers: {} } as InternalAxiosRequestConfig;
    }

    it('stamps the PARAMETERIZED route, never the resolved URL', () => {
      requestInterceptor(configFor('/api/colonel/organizations/org_9f3a2b1c8d7e6f50'));

      expect(resolveApiRoute()).toBe('/api/colonel/organizations/:org_id');
    });

    it('never retains a raw client IP from a resolved admin path', () => {
      // /api/colonel/banned-ips/:ip is a real request (AdminBannedIps.vue).
      requestInterceptor(configFor('/api/colonel/banned-ips/203.0.113.5'));

      const route = resolveApiRoute();
      expect(route).not.toContain('203.0.113.5');
      expect(route).toBe('/api/colonel/banned-ips/:id');
    });

    it('drops the query string rather than scrubbing it', () => {
      requestInterceptor(configFor('/api/v2/secret/conceal?token=abc123'));

      expect(resolveApiRoute()).not.toContain('token');
    });

    it('clears the slot when a request carries no url', () => {
      requestInterceptor(configFor('/api/v2/status'));
      requestInterceptor(configFor(undefined));

      expect(resolveApiRoute()).toBeUndefined();
    });
  });

  // ==========================================================================
  // API-route slot LIFECYCLE
  //
  // The slot used to be stamped on request and never cleared, so after the
  // first API call of a session every later gracefulParse failure — including
  // ones with no axios call behind them (the bootstrap payload, a
  // sessionStorage bag) — was tagged with the last route that went out. Not a
  // leak (the value is parameterized), but a confidently WRONG diagnostic tag
  // sends an operator to an endpoint that never ran.
  //
  // Two properties, both required, and the pair is why the release is deferred
  // and reference-counted rather than a plain clear-on-settle.
  // ==========================================================================
  describe('api-route slot lifecycle', () => {
    beforeEach(() => {
      resetApiRouteContext();
      resetApiRouteSlotLifecycle();
    });

    afterEach(() => {
      resetApiRouteContext();
      resetApiRouteSlotLifecycle();
    });

    function configFor(url: string): InternalAxiosRequestConfig {
      return { url, headers: {} } as InternalAxiosRequestConfig;
    }

    const okResponse = () => ({ headers: {}, data: {}, status: 200 }) as unknown as AxiosResponse;

    /** Lets the whole microtask queue drain, then one macrotask. */
    const settleTimers = () => new Promise((resolve) => setTimeout(resolve, 0));

    it("SURVIVES the response interceptor and the caller's microtask continuation", async () => {
      // This is the property a naive clear-on-settle breaks: the consumer of
      // the slot is the awaiting caller, which parses the response body in a
      // microtask queued after the interceptor returns.
      requestInterceptor(configFor('/api/colonel/organizations/org_9f3a2b1c8d7e6f50'));
      responseInterceptor(okResponse());

      expect(resolveApiRoute()).toBe('/api/colonel/organizations/:org_id');
      await Promise.resolve();
      expect(resolveApiRoute()).toBe('/api/colonel/organizations/:org_id');
    });

    it('is released once the request has fully settled', async () => {
      requestInterceptor(configFor('/api/colonel/organizations/org_9f3a2b1c8d7e6f50'));
      responseInterceptor(okResponse());
      await settleTimers();

      expect(resolveApiRoute()).toBeUndefined();
    });

    it('is released on a FAILED request too', async () => {
      requestInterceptor(configFor('/api/v2/secret/conceal'));
      await errorInterceptor(
        createAxiosError({ url: '/api/v2/secret/conceal', status: 500 })
      ).catch(() => undefined);
      await settleTimers();

      expect(resolveApiRoute()).toBeUndefined();
    });

    it('does NOT clear while another request is still in flight', async () => {
      requestInterceptor(configFor('/api/v2/status'));
      requestInterceptor(configFor('/api/colonel/organizations/org_9f3a2b1c8d7e6f50'));
      // The first request settles while the second is still open.
      responseInterceptor(okResponse());
      await settleTimers();

      // Degrades to the pre-existing last-writer-wins behaviour, never to an
      // empty slot.
      expect(resolveApiRoute()).toBe('/api/colonel/organizations/:org_id');

      responseInterceptor(okResponse());
      await settleTimers();
      expect(resolveApiRoute()).toBeUndefined();
    });

    it('does not misattribute a later non-axios parse to the last route', async () => {
      requestInterceptor(configFor('/api/colonel/organizations/org_9f3a2b1c8d7e6f50'));
      responseInterceptor(okResponse());
      await settleTimers();

      // Stand-in for a bootstrap / sessionStorage gracefulParse failure that
      // happens long after any HTTP call.
      expect(resolveApiRoute()).toBeUndefined();
    });
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
