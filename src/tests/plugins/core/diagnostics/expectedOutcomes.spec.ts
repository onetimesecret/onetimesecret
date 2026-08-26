// src/tests/plugins/core/diagnostics/expectedOutcomes.spec.ts
//
// Tests for the expected-transport-outcome noise filter (#4286): request-
// shaped errors that represent the product working (an already-consumed
// secret, a cancelled request, client connectivity) must never reach Sentry,
// while everything else — including 5xx, which are OUR failures — must keep
// reporting.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ErrorEvent, EventHint } from '@sentry/core';
import type { Router, RouteLocationNormalizedLoaded } from 'vue-router';

import {
  EXPECTED_TRANSPORT_OUTCOMES,
  isExpectedTransportOutcome,
} from '@/plugins/core/diagnostics/expectedOutcomes';

// ---------------------------------------------------------------------------
// Unit tests (pure module, no Sentry wiring)
// ---------------------------------------------------------------------------

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

describe('isExpectedTransportOutcome — drops', () => {
  it('a 404 on the secret-fetch path (already viewed, burned, or expired)', () => {
    expect(
      isExpectedTransportOutcome(
        hintFor({ url: '/api/v3/guest/secret/abc123', method: 'get', status: 404 })
      )
    ).toBe(true);
  });

  it('a 404 on the reveal path', () => {
    expect(
      isExpectedTransportOutcome(
        hintFor({ url: '/api/v3/guest/secret/abc123/reveal', method: 'post', status: 404 })
      )
    ).toBe(true);
  });

  it.each([
    { code: 'ERR_CANCELED', name: 'CanceledError', message: 'canceled' },
    { code: 'ECONNABORTED', message: 'Request aborted' },
    { name: 'AbortError' },
  ])('a cancelled/aborted request: %o', (shape) => {
    expect(
      isExpectedTransportOutcome(
        hintFor({ url: '/api/v3/guest/secret/abc123', method: 'get', ...shape })
      )
    ).toBe(true);
  });

  it('a no-response network error', () => {
    expect(
      isExpectedTransportOutcome(
        hintFor({
          url: '/api/v3/guest/secret/abc123',
          method: 'get',
          code: 'ERR_NETWORK',
          message: 'Network Error',
        })
      )
    ).toBe(true);
  });
});

describe('isExpectedTransportOutcome — keeps reporting', () => {
  it.each([500, 502, 503, 520])(
    'server failures (status %d) — these are ours, not the client’s',
    (status) => {
      expect(
        isExpectedTransportOutcome(
          hintFor({ url: '/api/v3/guest/secret/abc123', method: 'get', status })
        )
      ).toBe(false);
    }
  );

  it.each([400, 401, 403, 409, 410, 422, 429])(
    'other 4xx statuses (status %d) — only 404 is treated as expected noise here',
    (status) => {
      expect(
        isExpectedTransportOutcome(
          hintFor({ url: '/api/v3/secret/conceal', method: 'post', status })
        )
      ).toBe(false);
    }
  );

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

describe('EXPECTED_TRANSPORT_OUTCOMES', () => {
  it('is exactly aborted, network, and 404 — nothing broader', () => {
    expect([...EXPECTED_TRANSPORT_OUTCOMES].sort()).toEqual(['404', 'aborted', 'network']);
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

describe('beforeSend integration', () => {
  const originalConsoleDebug = console.debug;

  function getBeforeSend(): (event: ErrorEvent, hint?: EventHint) => ErrorEvent | null {
    resetCapturedOptions();
    createDiagnostics({
      host: 'example.com',
      config: {
        sentry: { dsn: 'https://key@sentry.io/123', environment: 'test', release: '1.0.0' },
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
  });

  it('drops a 404 on the secret-fetch path before scrubbing/grouping run', () => {
    const handler = getBeforeSend();

    const result = handler(
      {
        exception: {
          values: [{ type: 'AxiosError', value: 'Request failed with status code 404' }],
        },
      },
      hintFor({ url: '/api/v3/guest/secret/abc123', method: 'get', status: 404 })
    );

    expect(result).toBeNull();
  });

  it('drops an aborted request', () => {
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'AxiosError', value: 'Request aborted' }] } },
      hintFor({
        url: '/api/v3/guest/secret/abc123',
        method: 'get',
        code: 'ECONNABORTED',
        message: 'Request aborted',
      })
    );

    expect(result).toBeNull();
  });

  it('drops a network error', () => {
    const handler = getBeforeSend();

    const result = handler(
      { exception: { values: [{ type: 'AxiosError', value: 'Network Error' }] } },
      hintFor({
        url: '/api/v3/guest/secret/abc123',
        method: 'get',
        code: 'ERR_NETWORK',
        message: 'Network Error',
      })
    );

    expect(result).toBeNull();
  });

  it('still reports a 503 (ours, not the client’s) and groups it separately from a 404', () => {
    const handler = getBeforeSend();

    const result = handler(
      {
        exception: {
          values: [{ type: 'AxiosError', value: 'Request failed with status code 503' }],
        },
      },
      hintFor({ url: '/api/v3/guest/secret/abc123', method: 'get', status: 503 })
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
