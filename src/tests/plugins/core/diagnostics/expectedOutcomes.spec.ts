// src/tests/plugins/core/diagnostics/expectedOutcomes.spec.ts
//
// Tests for the expected-transport-outcome noise filter (#4286): request-
// shaped errors that represent the product working (an already-consumed
// secret, a cancelled request, a client that is offline) must never reach
// Sentry, while everything else — 5xx, timeouts, and 404s from anywhere but
// an identifier-addressed route — must keep reporting.
//
// The negative cases below are the point of the suite. A filter like this
// fails silently by definition: over-dropping produces no error, no test
// failure, and no Sentry event to notice the absence of. So each drop rule is
// pinned from BOTH sides — the case it must drop, and the near-miss case it
// must not.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ErrorEvent, EventHint } from '@sentry/core';
import type { Router, RouteLocationNormalizedLoaded } from 'vue-router';

import { isExpectedTransportOutcome } from '@/plugins/core/diagnostics/expectedOutcomes';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/**
 * A 62-char base-36 identifier, the current shape (v0.24+). Realistic width
 * matters here: the filter recognizes an identifier route BY the identifier's
 * shape, so a placeholder like `abc123` would exercise a path the app never
 * produces.
 */
const SECRET_ID = `${'x9k2m4p7'.repeat(7)}abcdef`;

/** A 31-char legacy identifier (v0.23), still accepted. */
const LEGACY_ID = 'q1w2e3r4t5y6u7i8o9p0a1s2d3f4g5h';

/** Builds an axios-shaped request error; structural, not instanceof. */
function requestError(overrides: {
  url: string;
  method?: string;
  status?: number;
  code?: string;
  name?: string;
  message?: string;
}): Error {
  const err = new Error(overrides.message ?? 'Request failed') as Error & {
    config: { url: string; method?: string };
    response?: { status: number };
    code?: string;
  };
  err.config = { url: overrides.url, method: overrides.method };
  if (overrides.status !== undefined) {
    err.response = { status: overrides.status };
  }
  if (overrides.code !== undefined) {
    err.code = overrides.code;
  }
  if (overrides.name !== undefined) {
    Object.defineProperty(err, 'name', { value: overrides.name });
  }
  return err;
}

function hintFor(overrides: Parameters<typeof requestError>[0]): EventHint {
  return { originalException: requestError(overrides) };
}

/**
 * Overrides `navigator.onLine`, which jsdom hard-codes to true. Defined as a
 * configurable own property so `delete` restores the prototype getter.
 */
function setOnLine(value: boolean): void {
  Object.defineProperty(globalThis.navigator, 'onLine', {
    configurable: true,
    get: () => value,
  });
}

function restoreOnLine(): void {
  delete (globalThis.navigator as unknown as { onLine?: boolean }).onLine;
}

// ---------------------------------------------------------------------------
// Unit tests (pure module, no Sentry wiring)
// ---------------------------------------------------------------------------

describe('isExpectedTransportOutcome — 404 is scoped to identifier routes', () => {
  it.each([
    ['guest secret fetch', `/api/v3/guest/secret/${SECRET_ID}`, 'get'],
    ['authenticated secret fetch', `/api/v3/secret/${SECRET_ID}`, 'get'],
    ['secret reveal', `/api/v3/guest/secret/${SECRET_ID}/reveal`, 'post'],
    ['receipt fetch', `/api/v3/receipt/${SECRET_ID}`, 'get'],
    ['receipt burn', `/api/v3/receipt/${SECRET_ID}/burn`, 'post'],
    ['legacy 31-char identifier', `/api/v3/guest/secret/${LEGACY_ID}`, 'get'],
    ['absolute URL', `https://example.com/api/v3/guest/secret/${SECRET_ID}`, 'get'],
    ['identifier route with a query string', `/api/v3/guest/secret/${SECRET_ID}?lang=de`, 'get'],
  ])('drops a 404 on %s (already viewed, burned, or expired)', (_label, url, method) => {
    expect(isExpectedTransportOutcome(hintFor({ url, method, status: 404 }))).toBe(true);
  });

  it.each([
    ['the conceal endpoint', '/api/v3/guest/secret/conceal', 'post'],
    ['the generate endpoint', '/api/v3/guest/secret/generate', 'post'],
    ['a mis-versioned path', `/api/v9/guest/secret/${SECRET_ID}/reveal/extra`, 'post'],
    ['an unknown action on a real identifier', `/api/v3/guest/secret/${SECRET_ID}/shred`, 'post'],
    ['a non-identifier resource', '/api/v3/organizations/acme', 'get'],
    ['a bare resource collection', '/api/v3/secret', 'get'],
    ['an identifier with no resource word before it', `/${SECRET_ID}`, 'get'],
    ['a too-short identifier', '/api/v3/guest/secret/abc123', 'get'],
  ])('keeps reporting a 404 on %s — that is a routing defect, not a consumed secret', (
    _label,
    url,
    method
  ) => {
    expect(isExpectedTransportOutcome(hintFor({ url, method, status: 404 }))).toBe(false);
  });
});

describe('isExpectedTransportOutcome — cancellations', () => {
  it.each([
    { code: 'ERR_CANCELED', name: 'CanceledError', message: 'canceled' },
    { code: 'ECONNABORTED', message: 'Request aborted' },
    { name: 'AbortError' },
  ])('drops a cancelled request: %o', (shape) => {
    expect(
      isExpectedTransportOutcome(
        hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', ...shape })
      )
    ).toBe(true);
  });

  it('drops a cancellation on any route, not just identifier routes', () => {
    expect(
      isExpectedTransportOutcome(
        hintFor({ url: '/api/v3/guest/secret/conceal', method: 'post', code: 'ERR_CANCELED' })
      )
    ).toBe(true);
  });

  it.each([
    { label: 'axios (clarifyTimeoutError)', code: 'ETIMEDOUT', message: 'timeout exceeded' },
    { label: 'fetch AbortSignal.timeout', name: 'TimeoutError' },
  ])(
    'keeps reporting a timeout — $label — a slow API is ours, not a cancellation',
    ({ code, name, message }) => {
      expect(
        isExpectedTransportOutcome(
          hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', code, name, message })
        )
      ).toBe(false);
    }
  );
});

describe('isExpectedTransportOutcome — network errors follow connectivity', () => {
  afterEach(restoreOnLine);

  const networkError = {
    url: `/api/v3/guest/secret/${SECRET_ID}`,
    method: 'get',
    code: 'ERR_NETWORK',
    message: 'Network Error',
  };

  it('drops a network error while the browser reports itself offline', () => {
    setOnLine(false);
    expect(isExpectedTransportOutcome(hintFor(networkError))).toBe(true);
  });

  it('keeps reporting a network error raised while the client believes it is online — DNS, TLS, CORS, or an unreachable deployment', () => {
    setOnLine(true);
    expect(isExpectedTransportOutcome(hintFor(networkError))).toBe(false);
  });

  it('keeps reporting when connectivity is unknowable', () => {
    // No navigator.onLine to consult: report rather than guess.
    Object.defineProperty(globalThis.navigator, 'onLine', {
      configurable: true,
      get: () => undefined,
    });
    expect(isExpectedTransportOutcome(hintFor(networkError))).toBe(false);
  });
});

describe('isExpectedTransportOutcome — keeps reporting', () => {
  it.each([500, 502, 503, 520])(
    'server failures (status %d) — these are ours, not the client’s',
    (status) => {
      expect(
        isExpectedTransportOutcome(
          hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', status })
        )
      ).toBe(false);
    }
  );

  it.each([400, 401, 403, 409, 410, 422, 429])(
    'other 4xx statuses (status %d) — only 404 is treated as expected noise here',
    (status) => {
      expect(
        isExpectedTransportOutcome(
          hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', status })
        )
      ).toBe(false);
    }
  );

  it('an unrecognized failure class', () => {
    expect(
      isExpectedTransportOutcome(
        hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', name: 'WeirdError' })
      )
    ).toBe(false);
  });

  it('a plain, non-request-shaped error', () => {
    expect(isExpectedTransportOutcome({ originalException: new Error('boom') })).toBe(false);
  });

  it.each([undefined, null, 'a string'])(
    'a missing or non-object originalException: %j',
    (originalException) => {
      expect(isExpectedTransportOutcome({ originalException } as EventHint)).toBe(false);
    }
  );

  it('an undefined hint', () => {
    expect(isExpectedTransportOutcome(undefined)).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// beforeSend integration — the filter runs first and short-circuits the rest
// of the pipeline (scrubbing, grouping) for dropped events.
// ---------------------------------------------------------------------------

const {
  mockGetBootstrapValue,
  MockBrowserClient,
  MockScope,
  getCapturedClientOptions,
  resetCapturedOptions,
} = vi.hoisted(() => {
  const mockGetBootstrapValue = vi.fn();
  let capturedClientOptions: Record<string, unknown> | null = null;

  class MockBrowserClient {
    constructor(options: Record<string, unknown>) {
      capturedClientOptions = options;
    }
    init = vi.fn();
    close = vi.fn().mockResolvedValue(undefined);
  }

  class MockScope {
    setClient = vi.fn();
    setTag = vi.fn();
    setUser = vi.fn();
  }

  return {
    mockGetBootstrapValue,
    MockBrowserClient,
    MockScope,
    getCapturedClientOptions: () => capturedClientOptions,
    resetCapturedOptions: () => {
      capturedClientOptions = null;
    },
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

import { createDiagnostics } from '@/plugins/core/enableDiagnostics';

function createMockRouter(): Router {
  return {
    resolve: vi.fn(),
    currentRoute: {
      value: { params: {}, meta: {}, matched: [] } as unknown as RouteLocationNormalizedLoaded,
    },
    afterEach: vi.fn(() => vi.fn()),
  } as unknown as Router;
}

const TEST_HOST = 'example.com';

describe('beforeSend integration', () => {
  const originalConsoleDebug = console.debug;

  function getBeforeSend(): (event: ErrorEvent, hint?: EventHint) => ErrorEvent | null {
    resetCapturedOptions();
    createDiagnostics({
      host: TEST_HOST,
      config: {
        sentry: { dsn: 'https://key@example.com/123', environment: 'test', release: '1.0.0' },
      },
      router: createMockRouter(),
    });
    const options = getCapturedClientOptions();
    if (!options) throw new Error('BrowserClient constructor was never called');
    return options.beforeSend as (event: ErrorEvent, hint?: EventHint) => ErrorEvent | null;
  }

  beforeEach(() => {
    vi.clearAllMocks();
    console.debug = vi.fn();
    mockGetBootstrapValue.mockReturnValue(null);
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
    restoreOnLine();
  });

  it('drops a 404 on the secret-fetch path before scrubbing/grouping run', () => {
    const handler = getBeforeSend();

    const result = handler(
      {
        exception: {
          values: [{ type: 'AxiosError', value: 'Request failed with status code 404' }],
        },
      },
      hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', status: 404 })
    );

    expect(result).toBeNull();
  });

  it('drops an aborted request', () => {
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'AxiosError', value: 'Request aborted' }] } },
      hintFor({
        url: `/api/v3/guest/secret/${SECRET_ID}`,
        method: 'get',
        code: 'ECONNABORTED',
        message: 'Request aborted',
      })
    );

    expect(result).toBeNull();
  });

  it('drops a network error raised while offline', () => {
    setOnLine(false);
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'AxiosError', value: 'Network Error' }] } },
      hintFor({
        url: `/api/v3/guest/secret/${SECRET_ID}`,
        method: 'get',
        code: 'ERR_NETWORK',
        message: 'Network Error',
      })
    );

    expect(result).toBeNull();
  });

  it('reports an unreachable API while online, grouped as a network outcome', () => {
    setOnLine(true);
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'AxiosError', value: 'Network Error' }] } },
      hintFor({
        url: `/api/v3/guest/secret/${SECRET_ID}`,
        method: 'get',
        code: 'ERR_NETWORK',
        message: 'Network Error',
      })
    ) as ErrorEvent;

    expect(result).not.toBeNull();
    expect(result.fingerprint).toEqual([
      'api-error',
      'GET',
      '/api/v3/guest/secret/[REDACTED]',
      'network',
    ]);
  });

  it('reports a 404 from a non-identifier endpoint — a routing defect stays visible', () => {
    const handler = getBeforeSend();

    const result = handler(
      {
        exception: {
          values: [{ type: 'AxiosError', value: 'Request failed with status code 404' }],
        },
      },
      hintFor({ url: '/api/v3/guest/secret/conceal', method: 'post', status: 404 })
    ) as ErrorEvent;

    expect(result).not.toBeNull();
    expect(result.fingerprint).toEqual([
      'api-error',
      'POST',
      '/api/v3/guest/secret/[REDACTED]',
      '404',
    ]);
  });

  it('reports a timeout, grouped separately from an abort', () => {
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'AxiosError', value: 'timeout exceeded' }] } },
      hintFor({
        url: `/api/v3/guest/secret/${SECRET_ID}`,
        method: 'get',
        code: 'ETIMEDOUT',
        message: 'timeout of 5000ms exceeded',
      })
    ) as ErrorEvent;

    expect(result).not.toBeNull();
    expect(result.fingerprint).toEqual([
      'api-error',
      'GET',
      '/api/v3/guest/secret/[REDACTED]',
      'timeout',
    ]);
  });

  it('still reports a 503 (ours, not the client’s) and groups it separately from a 404', () => {
    const handler = getBeforeSend();

    const result = handler(
      {
        exception: {
          values: [{ type: 'AxiosError', value: 'Request failed with status code 503' }],
        },
      },
      hintFor({ url: `/api/v3/guest/secret/${SECRET_ID}`, method: 'get', status: 503 })
    ) as ErrorEvent;

    expect(result).not.toBeNull();
    expect(result.fingerprint).toEqual([
      'api-error',
      'GET',
      '/api/v3/guest/secret/[REDACTED]',
      '503',
    ]);
  });

  it('still reports non-request-shaped errors', () => {
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'TypeError', value: 'boom' }] } },
      { originalException: new TypeError('boom') }
    );

    expect(result).not.toBeNull();
  });
});
