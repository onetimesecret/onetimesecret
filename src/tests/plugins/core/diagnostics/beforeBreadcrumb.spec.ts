// src/tests/plugins/core/beforeBreadcrumb.spec.ts
//
// Tests for the beforeBreadcrumb handler created by createDiagnostics.
// Tests navigation breadcrumbs, HTTP breadcrumbs (xhr/fetch), and edge cases.
//
// The handler is accessed by calling createDiagnostics() and extracting
// beforeBreadcrumb from the captured BrowserClient constructor options.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Breadcrumb } from '@sentry/core';
import type { Router } from 'vue-router';

// ---------------------------------------------------------------------------
// Mocks - must use vi.hoisted() for variables used in vi.mock factories
// ---------------------------------------------------------------------------

const {
  mockSetTag,
  mockSetUser,
  mockSetClient,
  mockClientInit,
  mockClientClose,
  mockGetBootstrapValue,
  MockBrowserClient,
  MockScope,
  getCapturedClientOptions,
  resetCapturedOptions,
} = vi.hoisted(() => {
  const mockSetTag = vi.fn();
  // Actor identity (#privacy boundary) writes setUser on the isolated scope.
  const mockSetUser = vi.fn();
  const mockSetClient = vi.fn();
  const mockClientInit = vi.fn();
  const mockClientClose = vi.fn().mockResolvedValue(undefined);
  const mockGetBootstrapValue = vi.fn();

  let capturedClientOptions: Record<string, unknown> | null = null;

  class MockBrowserClient {
    constructor(options: Record<string, unknown>) {
      capturedClientOptions = options;
    }
    init = mockClientInit;
    close = mockClientClose;
  }

  class MockScope {
    setClient = mockSetClient;
    setTag = mockSetTag;
    setUser = mockSetUser;
  }

  function getCapturedClientOptions() {
    return capturedClientOptions;
  }

  function resetCapturedOptions() {
    capturedClientOptions = null;
  }

  return {
    mockSetTag,
    mockSetUser,
    mockSetClient,
    mockClientInit,
    mockClientClose,
    mockGetBootstrapValue,
    MockBrowserClient,
    MockScope,
    getCapturedClientOptions,
    resetCapturedOptions,
  };
});

vi.mock('@/services/bootstrap.service', () => ({
  getBootstrapValue: mockGetBootstrapValue,
}));

vi.mock('@sentry/browser', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@sentry/browser')>();
  return {
    ...actual,
    BrowserClient: MockBrowserClient,
    Scope: MockScope,
  };
});

vi.mock('@sentry/vue', () => ({
  browserTracingIntegration: vi.fn().mockReturnValue({ name: 'BrowserTracing' }),
}));

vi.mock('@/services/diagnostics.service', () => ({
  initDiagnostics: vi.fn(),
}));

// ---------------------------------------------------------------------------
// Import production code after mocks are set up
// ---------------------------------------------------------------------------

import { createDiagnostics } from '@/plugins/core/enableDiagnostics';
import type { RouteMeta } from '@/types/router';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

const baseConfig = {
  sentry: {
    dsn: 'https://key@sentry.io/123',
    environment: 'test',
    release: '1.0.0',
  },
};

/** Test fixture host - uses 'localhost' to avoid CodeQL regex anchor false positives */
const TEST_HOST = 'example.com';

/**
 * Creates a mock router for testing beforeBreadcrumb handler.
 * The resolve() function is configured per-test by mutating this router.
 */
function createMockRouter(): Router {
  return {
    resolve: vi.fn((path: string) => ({
      params: {},
      meta: {},
    })),
    currentRoute: {
      value: {
        params: {},
        meta: {},
      },
    },
    afterEach: vi.fn(),
  } as unknown as Router;
}

/**
 * Extracts the beforeBreadcrumb handler from captured BrowserClient options.
 */
function getBeforeBreadcrumb(): (breadcrumb: Breadcrumb) => Breadcrumb | null {
  const options = getCapturedClientOptions();
  if (!options) throw new Error('BrowserClient constructor was never called');
  return options.beforeBreadcrumb as (breadcrumb: Breadcrumb) => Breadcrumb | null;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('beforeBreadcrumb handler', () => {
  const originalConsoleDebug = console.debug;
  let mockRouter: Router;

  beforeEach(() => {
    vi.clearAllMocks();
    resetCapturedOptions();
    console.debug = vi.fn();
    mockGetBootstrapValue.mockReturnValue(null);

    // Create a fresh router for each test
    mockRouter = createMockRouter();

    // Wire up createDiagnostics to capture the beforeBreadcrumb handler
    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: mockRouter,
    });
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  describe('navigation breadcrumbs', () => {
    it('scrubs navigation breadcrumb "to" URL using route params', () => {
      // Configure router.resolve for this test
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation((path: string) => {
        if (path === '/secret/abc123') {
          return { params: { secretKey: 'abc123' }, meta: { sentryScrubParams: undefined } };
        }
        return { params: {}, meta: {} };
      });

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '/',
          to: '/secret/abc123',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.to).toBe('/secret/[REDACTED]');
    });

    it('scrubs navigation breadcrumb "from" URL', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation((path: string) => {
        if (path === '/secret/xyz789') {
          return { params: { secretKey: 'xyz789' }, meta: {} };
        }
        return { params: {}, meta: {} };
      });

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '/secret/xyz789',
          to: '/',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.from).toBe('/secret/[REDACTED]');
    });

    it('respects sentryScrubParams: false - no scrubbing', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation((path: string) => {
        if (path === '/colonel/admin') {
          return { params: { adminId: 'admin' }, meta: { sentryScrubParams: false } };
        }
        return { params: {}, meta: {} };
      });

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '/',
          to: '/colonel/admin',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.to).toBe('/colonel/admin');
    });

    // -----------------------------------------------------------------------
    // PII pattern net on navigation breadcrumbs: an email in the query must be
    // redacted even when the route opts out of param scrubbing or has no path
    // params. Opt-out governs path-param VALUE scrubbing only, not the email/
    // secret net. (Policy: no PII in the URL — src/utils/pii.ts, README.)
    // -----------------------------------------------------------------------
    it('scrubs an email in the query even when sentryScrubParams: false', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation(() => ({
        params: {},
        meta: { sentryScrubParams: false },
      }));

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: { from: '/', to: '/check-email?email=user@example.com' },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.to).toBe('/check-email?email=[EMAIL_REDACTED]');
    });

    it('scrubs an email in the query on a route with no path params', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation(() => ({
        params: {},
        meta: {},
      }));

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: { from: '/pricing?email=user@example.com', to: '/signin' },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.from).toBe('/pricing?email=[EMAIL_REDACTED]');
    });

    it('preserves benign billing params verbatim (no over-redaction)', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation(() => ({
        params: {},
        meta: { sentryScrubParams: false },
      }));

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: { from: '/', to: '/check-email?product=identity&interval=month' },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.to).toBe('/check-email?product=identity&interval=month');
    });

    it('scrubs only named params when sentryScrubParams is string[]', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation((path: string) => {
        if (path === '/user/john/token/secret123') {
          return {
            params: { username: 'john', token: 'secret123' },
            meta: { sentryScrubParams: ['token'] },
          };
        }
        return { params: {}, meta: {} };
      });

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '/',
          to: '/user/john/token/secret123',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.to).toBe('/user/john/token/[REDACTED]');
      expect(result?.data?.to).toContain('john');
    });

    it('leaves breadcrumb unchanged when route has no params', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation(() => ({
        params: {},
        meta: {},
      }));

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '/',
          to: '/about',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.to).toBe('/about');
    });

    it('falls back to pattern scrubbing when router.resolve throws', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation(() => {
        throw new Error('Route not found');
      });

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '/',
          to: '/secret/abc123',
        },
      };

      const result = handler(breadcrumb);

      // Falls back to regex pattern scrubbing
      expect(result?.data?.to).toBe('/secret/[REDACTED]');
    });
  });

  describe('HTTP breadcrumbs (xhr/fetch)', () => {
    it('scrubs xhr breadcrumb URL using regex patterns', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'xhr',
        data: {
          url: 'https://api.example.com/api/v3/secret/abc123',
          method: 'GET',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.url).toBe('https://api.example.com/api/v3/secret/[REDACTED]');
    });

    it('scrubs fetch breadcrumb URL using regex patterns', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: {
          url: 'https://api.example.com/api/v3/private/xyz789',
          method: 'POST',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.url).toBe('https://api.example.com/api/v3/private/[REDACTED]');
    });

    it('scrubs 62-char verifiable IDs in HTTP breadcrumbs', () => {
      // 62 lowercase alphanumeric characters (a-z, 0-9)
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'xhr',
        data: {
          url: `https://api.example.com/api/v3/unknown/${id62}`,
          method: 'GET',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.url).toBe('https://api.example.com/api/v3/unknown/[REDACTED]');
    });

    it('leaves non-sensitive HTTP URLs unchanged', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'xhr',
        data: {
          url: 'https://api.example.com/api/v3/colonel/status',
          method: 'GET',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.url).toBe('https://api.example.com/api/v3/colonel/status');
    });
  });

  describe('other breadcrumb categories', () => {
    it('passes through console breadcrumbs unchanged', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'console',
        message: 'Debug: processing secret abc123',
        level: 'info',
      };

      const result = handler(breadcrumb);

      expect(result).toEqual(breadcrumb);
    });

    it('passes through ui.click breadcrumbs unchanged', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'ui.click',
        message: 'body > div > button',
      };

      const result = handler(breadcrumb);

      expect(result).toEqual(breadcrumb);
    });

    it('handles breadcrumbs without data property', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        message: 'Page changed',
      };

      const result = handler(breadcrumb);

      expect(result).toEqual(breadcrumb);
    });

    it('handles HTTP breadcrumbs without url in data', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'xhr',
        data: {
          method: 'GET',
          status_code: 200,
        },
      };

      const result = handler(breadcrumb);

      expect(result).toEqual(breadcrumb);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // METADATA-ONLY POLICY (requirement 8)
  //
  // These assert the STRUCTURAL control, which is independent of the value
  // scrubbers above: `data` is reduced to a fixed allowlist per category, so a
  // key nobody reviewed cannot ride along.
  // ───────────────────────────────────────────────────────────────────────────
  describe('metadata-only breadcrumb policy', () => {
    it('keeps only metadata keys on fetch breadcrumbs', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: {
          url: 'https://api.example.com/api/v2/account',
          method: 'POST',
          status_code: 200,
          duration: 42,
          trace_id: 'abcdef',
          span_id: '123456',
          request_id: 'req-9',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data).toEqual({
        url: 'https://api.example.com/api/v2/account',
        method: 'POST',
        status_code: 200,
        duration: 42,
        trace_id: 'abcdef',
        span_id: '123456',
        request_id: 'req-9',
      });
    });

    it('folds timing in from the breadcrumb HINT, where the SDK actually puts it', () => {
      // @sentry/browser's fetch/xhr instrumentation passes
      // `{ startTimestamp, endTimestamp }` as the second argument and never
      // writes `data.duration`, so the allowlist entry for `duration` was inert
      // until this fold-in existed.
      const handler = getBeforeBreadcrumb() as (
        breadcrumb: Breadcrumb,
        hint?: unknown
      ) => Breadcrumb | null;
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: { url: 'https://api.example.com/api/v2/account', method: 'GET', status_code: 200 },
      };

      const result = handler(breadcrumb, { startTimestamp: 1000, endTimestamp: 1042 });

      expect(result?.data?.duration).toBe(42);
    });

    it('leaves duration absent when the hint carries no usable timing', () => {
      const handler = getBeforeBreadcrumb() as (
        breadcrumb: Breadcrumb,
        hint?: unknown
      ) => Breadcrumb | null;
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: { url: 'https://api.example.com/api/v2/account', method: 'GET' },
      };

      const result = handler(breadcrumb, { startTimestamp: 'nope', endTimestamp: undefined });

      expect(result?.data).not.toHaveProperty('duration');
    });

    it('drops request and response bodies from HTTP breadcrumbs', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: {
          url: 'https://api.example.com/api/v2/secret/conceal',
          method: 'POST',
          status_code: 200,
          request_body: { secret: 'hunter2', passphrase: 'swordfish' },
          response_body: '{"record":{"secret_key":"abc"}}',
          request_body_size: 128,
          response_body_size: 256,
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data).not.toHaveProperty('request_body');
      expect(result?.data).not.toHaveProperty('response_body');
      expect(JSON.stringify(result?.data)).not.toContain('hunter2');
      expect(JSON.stringify(result?.data)).not.toContain('swordfish');

      // DELIBERATE POLICY CHANGE, not a weakened privacy assertion: the two
      // *_body_size keys are BYTE COUNTS, not content. They were dropped by
      // proximity to `request_body` / `response_body`, which is the assertion
      // that is actually doing the work above and still holds. A size cannot be
      // reversed into a payload and carries no personal data at any value,
      // while "was the response empty, truncated, or full-size-but-wrong-shape"
      // is the first question asked on a schema failure — three causes that
      // share one status code. Removing no data at the cost of that distinction
      // is pure loss, so the counts are retained on purpose.
      expect(result?.data?.request_body_size).toBe(128);
      expect(result?.data?.response_body_size).toBe(256);
    });

    // The claim above — "a size is a BYTE COUNT, not content" — was a property
    // of @sentry/browser's typings, not of our code: the allowlist was
    // key-only, so a producer writing a STRING under a size key shipped it
    // verbatim. Every allowlisted key now declares a primitive type and a value
    // of any other type is dropped, which makes the claim structural.
    it('drops size keys whose value is not a number', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: {
          url: 'https://api.example.com/api/v2/secret/conceal',
          method: 'POST',
          request_body_size: '{"password":"hunter2"}',
          response_body_size: { nested: 'alice@example.com' },
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data).not.toHaveProperty('request_body_size');
      expect(result?.data).not.toHaveProperty('response_body_size');
      expect(JSON.stringify(result?.data)).not.toContain('hunter2');
      expect(JSON.stringify(result?.data)).not.toContain('alice@example.com');
      // The correctly typed keys on the same bag are untouched.
      expect(result?.data?.method).toBe('POST');
    });

    it('drops string-typed keys whose value is an object', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'xhr',
        data: {
          url: 'https://api.example.com/api/v2/account',
          method: 'GET',
          status_code: 200,
          trace_id: { leaked: 'bob@example.com' },
          request_id: ['carol@example.com'],
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data).not.toHaveProperty('trace_id');
      expect(result?.data).not.toHaveProperty('request_id');
      expect(JSON.stringify(result?.data)).not.toContain('@example.com');
      expect(result?.data?.status_code).toBe(200);
    });

    it('drops headers and cookies from HTTP breadcrumbs', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'xhr',
        data: {
          url: 'https://api.example.com/api/v2/account',
          method: 'GET',
          headers: { Authorization: 'Bearer tok_live_123', Cookie: 'sess=abc' },
          cookies: 'sess=abc',
          Authorization: 'Bearer tok_live_123',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data).toEqual({
        url: 'https://api.example.com/api/v2/account',
        method: 'GET',
      });
      expect(JSON.stringify(result?.data)).not.toContain('Bearer');
      expect(JSON.stringify(result?.data)).not.toContain('sess=abc');
    });

    it('applies the allowlist to HTTP breadcrumbs that carry no url', () => {
      // Regression: the previous handler guarded on `data.url`, so a
      // body-carrying breadcrumb with no url skipped scrubbing entirely.
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'fetch',
        data: { method: 'POST', response_body: 'raw secret material' },
      };

      const result = handler(breadcrumb);

      expect(result?.data).toEqual({ method: 'POST' });
    });

    it('keeps only from/to on navigation breadcrumbs', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: { from: '/one', to: '/two', state: { email: 'user@example.com' } },
      };

      const result = handler(breadcrumb);

      expect(result?.data).toEqual({ from: '/one', to: '/two' });
    });

    it('scrubs emails interpolated into console breadcrumb messages', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'console',
        level: 'warn',
        message: 'lookup failed for user@example.com',
      };

      const result = handler(breadcrumb);

      expect(result?.message).not.toContain('user@example.com');
    });

    it('scrubs verifiable identifiers in ui.click breadcrumb messages', () => {
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'ui.click',
        message: `a[href="/secret/${id62}"]`,
      };

      const result = handler(breadcrumb);

      expect(result?.message).not.toContain(id62);
    });

    it('drops the raw argument list from console breadcrumbs', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'console',
        message: 'request failed',
        data: { arguments: [{ passphrase: 'swordfish' }], logger: 'console' },
      };

      const result = handler(breadcrumb);

      expect(result?.data).not.toHaveProperty('arguments');
      expect(result?.data).toEqual({ logger: 'console' });
    });
  });

  describe('edge cases', () => {
    it('handles navigation with empty string path', () => {
      (mockRouter.resolve as ReturnType<typeof vi.fn>).mockImplementation(() => ({
        params: {},
        meta: {},
      }));

      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: '',
          to: '/home',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.from).toBe('');
    });

    // Was: "handles non-string path values gracefully", asserting that `null`
    // and `123` passed THROUGH unchanged. Graceful still means "does not
    // throw", but pass-through was the hole: `from`/`to` are URLs, the
    // allowlist was key-only, and a producer writing an object under either key
    // shipped it whole. They are now type-checked and dropped, which is a
    // tightening of the same assertion, not a relaxation of it.
    it('drops non-string path values without throwing', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: null,
          to: 123,
        },
      };

      const result = handler(breadcrumb);

      expect(result).not.toBeNull();
      expect(result?.data).toBeUndefined();
    });

    it('drops an object-valued navigation path', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: { leaked: 'dave@example.com' },
          to: '/home',
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data).not.toHaveProperty('from');
      expect(JSON.stringify(result?.data)).not.toContain('dave@example.com');
      expect(result?.data?.to).toBe('/home');
    });
  });
});
