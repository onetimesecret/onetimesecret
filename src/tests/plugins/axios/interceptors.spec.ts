// src/tests/plugins/axios/interceptors.spec.ts

/**
 * Tests for axios interceptors (src/plugins/axios/interceptors.ts)
 *
 * Covers:
 * - errorInterceptor breadcrumb functionality (Sentry integration)
 * - URL scrubbing for sensitive paths
 * - CSRF token preservation during errors
 *
 * Run:
 *   pnpm vitest run src/tests/plugins/axios/interceptors.spec.ts
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import axios, { type AxiosError, type AxiosResponse } from 'axios';
import * as Sentry from '@sentry/browser';

// ---------------------------------------------------------------------------
// Mock setup - must be before imports that use these modules
// ---------------------------------------------------------------------------

vi.mock('@sentry/browser', () => ({
  addBreadcrumb: vi.fn(),
}));

// Mock the CSRF store - use a module-level object so we can spy on it
const mockCsrfStore = {
  shrimp: 'mock-csrf-token',
  updateShrimp: vi.fn(),
};

vi.mock('@/shared/stores/csrfStore', () => ({
  useCsrfStore: () => mockCsrfStore,
}));

// Mock other stores used by requestInterceptor
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

// ---------------------------------------------------------------------------
// Import module under test AFTER mocks are set up
// ---------------------------------------------------------------------------
import { errorInterceptor, responseInterceptor, createLoggableShrimp } from '@/plugins/axios/interceptors';

// ---------------------------------------------------------------------------
// Helper: Create mock AxiosError objects
// ---------------------------------------------------------------------------
function createMockAxiosError(options: {
  url?: string;
  method?: string;
  status?: number;
  message?: string;
  responseHeaders?: Record<string, string>;
}): AxiosError {
  const { url, method, status, message = 'Request failed', responseHeaders = {} } = options;

  const error = new axios.AxiosError(
    message,
    status?.toString() ?? 'ERR_UNKNOWN',
    url !== undefined || method !== undefined
      ? ({
          url,
          method,
        } as any)
      : undefined,
    undefined,
    status !== undefined
      ? ({
          status,
          headers: responseHeaders,
          data: {},
        } as AxiosResponse)
      : undefined
  );

  return error;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
describe('axios interceptors', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockCsrfStore.updateShrimp.mockClear();
  });

  // ========================================================================
  // errorInterceptor - Breadcrumb functionality
  // ========================================================================
  describe('errorInterceptor', () => {
    describe('breadcrumb creation', () => {
      it('adds a breadcrumb when error occurs', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/users',
          method: 'get',
          status: 500,
          message: 'Internal Server Error',
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'http',
            category: 'http.client',
            level: 'error',
          })
        );
      });

      it('includes correct data fields in breadcrumb', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/colonel/admin',
          method: 'post',
          status: 403,
          message: 'Forbidden',
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'POST /api/v3/colonel/admin',
            data: expect.objectContaining({
              url: '/api/v3/colonel/admin',
              method: 'POST',
              status_code: 403,
              reason: 'Forbidden',
            }),
          })
        );
      });
    });

    describe('URL scrubbing', () => {
      it('scrubs /secret/ path identifiers', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/secret/abc123def456',
          method: 'get',
          status: 404,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'GET /api/v3/secret/[REDACTED]',
            data: expect.objectContaining({
              url: '/api/v3/secret/[REDACTED]',
            }),
          })
        );
      });

      it('scrubs /private/ path identifiers', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/private/xyz789',
          method: 'get',
          status: 404,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'GET /api/v3/private/[REDACTED]',
            data: expect.objectContaining({
              url: '/api/v3/private/[REDACTED]',
            }),
          })
        );
      });

      it('scrubs /receipt/ path identifiers', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/receipt/receipt123',
          method: 'get',
          status: 404,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'GET /api/v3/receipt/[REDACTED]',
            data: expect.objectContaining({
              url: '/api/v3/receipt/[REDACTED]',
            }),
          })
        );
      });

      it('scrubs /incoming/ path identifiers', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/incoming/incoming456',
          method: 'post',
          status: 400,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'POST /api/v3/incoming/[REDACTED]',
            data: expect.objectContaining({
              url: '/api/v3/incoming/[REDACTED]',
            }),
          })
        );
      });

      it('scrubs multiple sensitive segments in one URL', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/secret/abc123/private/xyz789',
          method: 'get',
          status: 500,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'GET /api/v3/secret/[REDACTED]/private/[REDACTED]',
            data: expect.objectContaining({
              url: '/api/v3/secret/[REDACTED]/private/[REDACTED]',
            }),
          })
        );
      });

      it('leaves non-sensitive URLs unchanged', async () => {
        const error = createMockAxiosError({
          url: '/api/v3/colonel/admin',
          method: 'get',
          status: 401,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'GET /api/v3/colonel/admin',
            data: expect.objectContaining({
              url: '/api/v3/colonel/admin',
            }),
          })
        );
      });
    });

    describe('method handling', () => {
      it('uppercases method from lowercase', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'get',
          status: 500,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'GET /api/test',
            data: expect.objectContaining({
              method: 'GET',
            }),
          })
        );
      });

      it('uppercases mixed case method', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'PoSt',
          status: 500,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'POST /api/test',
            data: expect.objectContaining({
              method: 'POST',
            }),
          })
        );
      });

      it('defaults method to HTTP when undefined', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: undefined,
          status: 500,
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'HTTP /api/test',
            data: expect.objectContaining({
              method: 'HTTP',
            }),
          })
        );
      });
    });

    describe('status code and reason capture', () => {
      it('captures status code from response', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'get',
          status: 404,
          message: 'Not Found',
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            data: expect.objectContaining({
              status_code: 404,
              reason: 'Not Found',
            }),
          })
        );
      });

      it('handles undefined status code when no response', async () => {
        // Network error - no response
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'get',
          status: undefined,
          message: 'Network Error',
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            data: expect.objectContaining({
              status_code: undefined,
              reason: 'Network Error',
            }),
          })
        );
      });
    });

    describe('graceful handling of edge cases', () => {
      it('handles error with empty config gracefully', async () => {
        const error = new axios.AxiosError('Request failed', 'ERR_UNKNOWN');
        // error.config is undefined by default

        await expect(errorInterceptor(error)).rejects.toBe(error);

        // Should not crash, should add breadcrumb with defaults
        expect(Sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            message: 'HTTP ',
            data: expect.objectContaining({
              url: '',
              method: 'HTTP',
            }),
          })
        );
      });

      it('handles error with null-like values gracefully', async () => {
        const error = createMockAxiosError({
          url: '',
          method: '',
          status: undefined,
          message: 'Unknown error',
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(Sentry.addBreadcrumb).toHaveBeenCalledTimes(1);
        // Empty method string.toUpperCase() returns '' which is falsy,
        // so || 'HTTP' kicks in - defaults to 'HTTP'
        expect(Sentry.addBreadcrumb).toHaveBeenCalledWith(
          expect.objectContaining({
            type: 'http',
            category: 'http.client',
            level: 'error',
            data: expect.objectContaining({
              url: '',
              method: 'HTTP',
            }),
          })
        );
      });
    });

    describe('CSRF token update on error', () => {
      it('updates CSRF token from error response headers', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'post',
          status: 403,
          responseHeaders: {
            'x-csrf-token': 'new-csrf-token-from-error',
          },
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(mockCsrfStore.updateShrimp).toHaveBeenCalledWith('new-csrf-token-from-error');
      });

      it('does not update CSRF token when header is missing', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'post',
          status: 500,
          responseHeaders: {},
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(mockCsrfStore.updateShrimp).not.toHaveBeenCalled();
      });

      it('does not update CSRF token when header is empty string', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'post',
          status: 403,
          responseHeaders: {
            'x-csrf-token': '',
          },
        });

        await expect(errorInterceptor(error)).rejects.toBe(error);

        expect(mockCsrfStore.updateShrimp).not.toHaveBeenCalled();
      });
    });

    describe('error propagation', () => {
      it('rejects with the original error (no gate keeping)', async () => {
        const error = createMockAxiosError({
          url: '/api/test',
          method: 'get',
          status: 500,
          message: 'Internal Server Error',
        });

        const rejection = errorInterceptor(error);

        await expect(rejection).rejects.toBe(error);
      });
    });
  });

  // ========================================================================
  // responseInterceptor - CSRF token update
  // ========================================================================
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

      expect(mockCsrfStore.updateShrimp).toHaveBeenCalledWith('new-csrf-token');
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

      expect(mockCsrfStore.updateShrimp).not.toHaveBeenCalled();
      expect(result).toBe(response);
    });
  });

  // ========================================================================
  // createLoggableShrimp - Token truncation for logging
  // ========================================================================
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
