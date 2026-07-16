// src/tests/plugins/core/beforeSend.spec.ts
//
// Tests for the beforeSend handler created by createDiagnostics.
// Tests exception message scrubbing, URL scrubbing based on route params,
// standalone message scrubbing, and edge cases.
//
// The handler is accessed by calling createDiagnostics() and extracting
// beforeSend from the captured BrowserClient constructor options.
//
// This file defines two tightly-coupled Sentry mock classes (MockBrowserClient
// and MockScope) inside a vi.hoisted() factory. Splitting them across files
// would obscure the mock-to-test-pairing for no structural benefit, so the
// file-level max-classes-per-file rule is disabled here.
/* eslint-disable max-classes-per-file */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ErrorEvent, TransactionEvent } from '@sentry/core';
import type { Router, RouteLocationNormalizedLoaded } from 'vue-router';
import type { RouteMeta } from '@/types/router';

// ---------------------------------------------------------------------------
// Mocks - must use vi.hoisted() for variables used in vi.mock factories
// ---------------------------------------------------------------------------

// Test-only mocks: two tightly-coupled mock classes for Sentry's BrowserClient
// and Scope. Splitting them across files would obscure the mock/test mapping.
// The file-level max-classes-per-file rule is disabled at the top of this
// file (see header) to allow both to live beside the tests that use them.
const {
  mockGetBootstrapValue,
  MockBrowserClient,
  MockScope,
  getCapturedClientOptions,
  resetCapturedOptions,
} = vi.hoisted(() => {
  const mockSetTag = vi.fn();
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
  }

  function getCapturedClientOptions() {
    return capturedClientOptions;
  }

  function resetCapturedOptions() {
    capturedClientOptions = null;
  }

  return {
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
 * Creates a mock router for testing beforeSend handler.
 * Uses currentRoute.value for the handler's route param access.
 */
function createMockRouter(config: {
  params: Record<string, string | string[]>;
  meta: Partial<RouteMeta>;
  resolve?: (path: string) => unknown;
}): Router {
  return {
    resolve: config.resolve ? vi.fn(config.resolve) : vi.fn(),
    currentRoute: {
      value: {
        params: config.params,
        meta: config.meta,
      } as RouteLocationNormalizedLoaded,
    },
    afterEach: vi.fn(),
  } as unknown as Router;
}

/**
 * Extracts the beforeSend handler from captured BrowserClient options.
 */
function getBeforeSend(): (event: ErrorEvent) => ErrorEvent | null {
  const options = getCapturedClientOptions();
  if (!options) throw new Error('BrowserClient constructor was never called');
  return options.beforeSend as (event: ErrorEvent) => ErrorEvent | null;
}

/**
 * Sets up createDiagnostics with a specific router configuration.
 * Must be called in each test that needs a specific route setup.
 */
function setupWithRouter(routerConfig: {
  params: Record<string, string | string[]>;
  meta: Partial<RouteMeta>;
  resolve?: (path: string) => unknown;
}): void {
  resetCapturedOptions();
  const mockRouter = createMockRouter(routerConfig);
  createDiagnostics({
    host: TEST_HOST,
    config: baseConfig,
    router: mockRouter,
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('beforeSend handler', () => {
  const originalConsoleDebug = console.debug;

  beforeEach(() => {
    vi.clearAllMocks();
    resetCapturedOptions();
    console.debug = vi.fn();
    mockGetBootstrapValue.mockReturnValue(null);
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  describe('exception message scrubbing', () => {
    it('scrubs email from exception message', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        exception: {
          values: [{ value: 'Failed for user@example.com' }],
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.exception?.values?.[0].value).toBe('Failed for [EMAIL_REDACTED]');
    });

    it('scrubs 62-char ID from exception message', () => {
      setupWithRouter({ params: {}, meta: {} });
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';

      const handler = getBeforeSend();
      const event: ErrorEvent = {
        exception: {
          values: [{ value: `Error processing ${id62}` }],
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.exception?.values?.[0].value).toBe('Error processing [REDACTED]');
    });

    it('scrubs sensitive path from exception message', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        exception: {
          values: [{ value: 'Not found: /secret/abc123' }],
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.exception?.values?.[0].value).toBe('Not found: /secret/[REDACTED]');
    });

    it('scrubs multiple exception values', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        exception: {
          values: [
            { value: 'Error for user@example.com' },
            { value: 'At path /private/xyz789' },
          ],
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.exception?.values?.[0].value).toBe('Error for [EMAIL_REDACTED]');
      expect(result.exception?.values?.[1].value).toBe('At path /private/[REDACTED]');
    });
  });

  describe('standalone message scrubbing', () => {
    it('scrubs email from event message', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        message: 'User user@example.com logged out',
      };

      const result = handler(event) as ErrorEvent;

      expect(result.message).toBe('User [EMAIL_REDACTED] logged out');
    });
  });

  describe('URL scrubbing based on route params', () => {
    it('scrubs request.url using route params', () => {
      setupWithRouter({
        params: { secretKey: 'abc123' },
        meta: { sentryScrubParams: undefined },
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          url: 'https://example.com/secret/abc123/view',
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.url).toBe('https://example.com/secret/[REDACTED]/view');
    });

    it('scrubs event.transaction', () => {
      setupWithRouter({
        params: { secretKey: 'xyz789' },
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        transaction: 'https://example.com/private/xyz789',
      };

      const result = handler(event) as ErrorEvent;

      expect(result.transaction).toBe('https://example.com/private/[REDACTED]');
    });

    it('scrubs breadcrumb URLs in event', () => {
      setupWithRouter({
        params: { token: 'secret456' },
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        breadcrumbs: [
          {
            category: 'navigation',
            data: {
              to: '/page/secret456',
              from: '/home',
            },
          },
          {
            category: 'xhr',
            data: {
              url: 'https://api.example.com/token/secret456',
            },
          },
        ],
      };

      const result = handler(event) as ErrorEvent;

      expect(result.breadcrumbs?.[0].data?.to).toBe('/page/[REDACTED]');
      expect(result.breadcrumbs?.[1].data?.url).toBe('https://api.example.com/token/[REDACTED]');
    });

    it('respects sentryScrubParams: false - skips URL scrubbing', () => {
      setupWithRouter({
        params: { adminId: 'admin123' },
        meta: { sentryScrubParams: false },
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          url: 'https://example.com/colonel/admin123',
        },
      };

      const result = handler(event) as ErrorEvent;

      // URL scrubbing is skipped, but message scrubbing still applies
      expect(result.request?.url).toBe('https://example.com/colonel/admin123');
    });

    it('still scrubs exception messages when sentryScrubParams: false', () => {
      setupWithRouter({
        params: { adminId: 'admin123' },
        meta: { sentryScrubParams: false },
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        exception: {
          values: [{ value: 'Error for user@example.com' }],
        },
        request: {
          url: 'https://example.com/colonel/admin123',
        },
      };

      const result = handler(event) as ErrorEvent;

      // Exception message scrubbing still applies
      expect(result.exception?.values?.[0].value).toBe('Error for [EMAIL_REDACTED]');
      // URL scrubbing is skipped
      expect(result.request?.url).toBe('https://example.com/colonel/admin123');
    });

    it('scrubs only named params when sentryScrubParams is string[]', () => {
      setupWithRouter({
        params: { username: 'john', token: 'secret123' },
        meta: { sentryScrubParams: ['token'] },
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          url: 'https://example.com/user/john/token/secret123',
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.url).toBe('https://example.com/user/john/token/[REDACTED]');
    });

    it('handles event with no route params', () => {
      setupWithRouter({
        params: {},
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          url: 'https://example.com/about',
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.url).toBe('https://example.com/about');
    });

    // -----------------------------------------------------------------------
    // PII pattern net: an email in a query string must be redacted from the
    // event URL/transaction regardless of route metadata. Path-param VALUE
    // scrubbing is opt-out-governed; the email/secret pattern net is not.
    // (Policy: no PII in the URL — src/utils/pii.ts, src/router/README.md.)
    // -----------------------------------------------------------------------
    it('scrubs an email in the query even when sentryScrubParams: false', () => {
      setupWithRouter({ params: {}, meta: { sentryScrubParams: false } });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: { url: 'https://example.com/check-email?email=user@example.com' },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.url).toBe('https://example.com/check-email?email=[EMAIL_REDACTED]');
    });

    it('scrubs an email in the query on a route with no path params', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: { url: 'https://example.com/pricing?email=user@example.com' },
        transaction: '/pricing?email=user@example.com',
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.url).toBe('https://example.com/pricing?email=[EMAIL_REDACTED]');
      expect(result.transaction).toBe('/pricing?email=[EMAIL_REDACTED]');
    });

    it('preserves benign billing params verbatim (no over-redaction)', () => {
      setupWithRouter({ params: {}, meta: { sentryScrubParams: false } });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: { url: 'https://example.com/check-email?product=identity&interval=month' },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.url).toBe(
        'https://example.com/check-email?product=identity&interval=month'
      );
    });

    // -----------------------------------------------------------------------
    // A3 — request.headers.Referer scrubbing. httpContextIntegration attaches
    // document.referrer as request.headers.Referer; it is a full URL and can
    // carry secret identifiers/emails, so it must go through the URL scrubber.
    // -----------------------------------------------------------------------
    it('scrubs a secret identifier in the Referer header', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          headers: { Referer: 'https://example.com/secret/abc123def456' },
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.headers?.Referer).toBe('https://example.com/secret/[REDACTED]');
    });

    it('scrubs a lowercase referer header variant', () => {
      setupWithRouter({ params: {}, meta: {} });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          headers: { referer: 'https://example.com/reveal?token=abc123' },
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.headers?.referer).toBe('https://example.com/reveal?token=[REDACTED]');
    });

    it('scrubs the route-param value in the Referer header (value layer)', () => {
      setupWithRouter({
        params: { secretKey: 'abc123' },
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        request: {
          headers: { Referer: 'https://example.com/page/abc123' },
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.request?.headers?.Referer).toBe('https://example.com/page/[REDACTED]');
    });

    it('removes secret property if present on event', () => {
      setupWithRouter({
        params: {},
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent & { secret?: string } = {
        secret: 'should-be-removed',
        message: 'Test event',
      };

      const result = handler(event) as ErrorEvent & { secret?: string };

      expect(result.secret).toBeUndefined();
    });
  });

  describe('edge cases', () => {
    it('handles event without exception values', () => {
      setupWithRouter({
        params: {},
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        exception: {
          values: undefined,
        },
      };

      const result = handler(event);

      expect(result).toEqual(event);
    });

    it('handles exception value without value property', () => {
      setupWithRouter({
        params: {},
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        exception: {
          values: [{ type: 'Error' }],
        },
      };

      const result = handler(event) as ErrorEvent;

      expect(result.exception?.values?.[0].type).toBe('Error');
    });

    it('handles breadcrumb without data', () => {
      setupWithRouter({
        params: { key: 'value' },
        meta: {},
      });
      const handler = getBeforeSend();

      const event: ErrorEvent = {
        breadcrumbs: [
          {
            category: 'console',
            message: 'Log message',
          },
        ],
      };

      const result = handler(event) as ErrorEvent;

      expect(result.breadcrumbs?.[0].message).toBe('Log message');
    });
  });
});

// ---------------------------------------------------------------------------
// beforeSendTransaction handler
// ---------------------------------------------------------------------------

describe('beforeSendTransaction handler', () => {
  const originalConsoleDebug = console.debug;

  beforeEach(() => {
    vi.clearAllMocks();
    resetCapturedOptions();
    console.debug = vi.fn();
    mockGetBootstrapValue.mockReturnValue(null);
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  function getBeforeSendTransaction(): (event: TransactionEvent) => TransactionEvent | null {
    const options = getCapturedClientOptions();
    if (!options) throw new Error('BrowserClient constructor was never called');
    return options.beforeSendTransaction as (event: TransactionEvent) => TransactionEvent | null;
  }

  it('is wired into client options', () => {
    setupWithRouter({ params: {}, meta: {} });
    expect(getBeforeSendTransaction()).toBeTypeOf('function');
  });

  it('scrubs raw pageload transaction name and request.url', () => {
    setupWithRouter({ params: {}, meta: {} });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/api/v2/secret/abc123def456',
      request: { url: 'https://eu.onetimesecret.com/api/v2/secret/abc123def456' },
    } as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    expect(result.transaction).toBe('/api/v2/secret/[REDACTED]');
    expect(result.request?.url).toBe('https://eu.onetimesecret.com/api/v2/secret/[REDACTED]');
  });

  it('scrubs span descriptions and URL data attributes', () => {
    setupWithRouter({ params: {}, meta: {} });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/secret/:secretKey',
      spans: [
        {
          description: 'GET /api/v2/secret/abc123def456',
          data: { 'http.url': 'https://eu.onetimesecret.com/api/v2/secret/abc123def456' },
        },
      ],
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    expect(result.spans?.[0].description).toBe('GET /api/v2/secret/[REDACTED]');
    expect(result.spans?.[0].data?.['http.url']).toBe(
      'https://eu.onetimesecret.com/api/v2/secret/[REDACTED]'
    );
    // Parameterized route names pass through untouched
    expect(result.transaction).toBe('/secret/:secretKey');
  });

  // A4 — span http.query is a bare query string; sensitive param values must
  // be redacted by name (and the id/email nets applied to the remainder).
  it('scrubs sensitive params in span http.query data', () => {
    setupWithRouter({ params: {}, meta: {} });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/secret/:secretKey',
      spans: [
        {
          description: 'GET /reveal',
          data: { 'http.query': 'token=abc123&email=user@example.com&interval=month' },
        },
      ],
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    expect(result.spans?.[0].data?.['http.query']).toBe(
      'token=[REDACTED]&email=[EMAIL_REDACTED]&interval=month'
    );
  });

  // A3 — Referer header scrubbing runs in the transaction handler too, via the
  // shared entrypoint.
  it('scrubs a secret identifier in the Referer header on transaction events', () => {
    setupWithRouter({ params: {}, meta: {} });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/secret/:secretKey',
      request: { headers: { Referer: 'https://example.com/secret/abc123def456' } },
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    expect(result.request?.headers?.Referer).toBe('https://example.com/secret/[REDACTED]');
  });

  // D2 — the transaction handler runs the route-param VALUE layer, not just the
  // pattern net. A benign-looking id that only route metadata knows is
  // sensitive must still be redacted from transaction events.
  it('runs the route-param value layer on transaction request.url (D2)', () => {
    setupWithRouter({
      params: { secretKey: 'abc123' },
      meta: {},
    });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/secret/:secretKey',
      // /page/abc123 is not a known sensitive path; only the route param
      // value 'abc123' marks it sensitive. The pattern net alone would miss it.
      request: { url: 'https://example.com/page/abc123' },
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    expect(result.request?.url).toBe('https://example.com/page/[REDACTED]');
  });

  it('honors sentryScrubParams: false for the transaction value layer', () => {
    setupWithRouter({
      params: { adminId: 'admin123' },
      meta: { sentryScrubParams: false },
    });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/colonel/:adminId',
      request: { url: 'https://example.com/page/admin123' },
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    // Value layer opted out; /page/ is not a known sensitive path, so it stays.
    expect(result.request?.url).toBe('https://example.com/page/admin123');
  });

  // #3794 C1 — Sentry stores span http.query as parsedUrl.search, WITH the
  // leading `?`. The first sensitive param must still be redacted.
  it('scrubs the first sensitive param in span http.query despite a leading `?`', () => {
    setupWithRouter({ params: {}, meta: {} });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/reveal',
      spans: [
        {
          description: 'GET /reveal',
          data: { 'http.query': '?token=hunter2&x=1' },
        },
      ],
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    expect(result.spans?.[0].data?.['http.query']).toBe('?token=[REDACTED]&x=1');
  });

  // #3794 C6 — the value layer must use the route the transaction belongs to
  // (resolved from event.request.url), not the live currentRoute. An in-flight
  // pageload transaction can outlive a navigation to a different route.
  it('resolves the value layer from the transaction URL, not the live current route (C6)', () => {
    // User has already navigated to /dashboard (no params, nothing to scrub)…
    setupWithRouter({
      params: {},
      meta: {},
      // …but the transaction's own URL resolves to a route whose param is
      // marked sensitive via metadata.
      resolve: (path: string) =>
        path === '/page/abc123'
          ? { meta: { sentryScrubParams: ['id'] }, params: { id: 'abc123' } }
          : { meta: {}, params: {} },
    });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/page/abc123',
      request: { url: 'https://example.com/page/abc123' },
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    // Live-route reading would return [] and leak abc123 (it is too short for
    // the pattern net); URL-resolved route context redacts it.
    expect(result.request?.url).toBe('https://example.com/page/[REDACTED]');
    expect(result.transaction).toBe('/page/[REDACTED]');
  });

  it('falls back to the current route when transaction URL resolution throws (C6)', () => {
    setupWithRouter({
      params: { secretKey: 'abc123' },
      meta: {},
      resolve: () => {
        throw new Error('no match');
      },
    });
    const handler = getBeforeSendTransaction();

    const event = {
      type: 'transaction',
      transaction: '/secret/:secretKey',
      request: { url: 'https://example.com/page/abc123' },
    } as unknown as TransactionEvent;

    const result = handler(event) as TransactionEvent;

    // Current-route fallback still applies the value layer.
    expect(result.request?.url).toBe('https://example.com/page/[REDACTED]');
  });
});
