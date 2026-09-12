// src/tests/plugins/core/diagnostics/grouping.spec.ts
//
// Tests for the explicit issue-grouping rules.
//
// The property under test: the grouping array must be identical for two
// events that describe the same defect, even when their stack frames,
// minified module names, and user-specific values differ — and must be
// ABSENT for events the rules do not understand, so Sentry's default
// grouping still applies there.

/* eslint-disable max-classes-per-file */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ErrorEvent, EventHint } from '@sentry/core';
import type { Router, RouteLocationNormalizedLoaded } from 'vue-router';

import { applyGroupingRules } from '@/plugins/core/diagnostics/grouping';

// ---------------------------------------------------------------------------
// Unit tests (pure module, no Sentry wiring)
// ---------------------------------------------------------------------------

const SCHEMA_MESSAGE =
  'Schema validation failed for SecretActivityResponse — 2 issue(s) [record.created, record.state]: record.created: invalid_type (Expected date)';

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

describe('applyGroupingRules — schema validation (Rule A)', () => {
  it('groups by schema name extracted from the message', () => {
    const event: ErrorEvent = {
      type: undefined,
      exception: { values: [{ type: 'Error', value: SCHEMA_MESSAGE }] },
    };

    applyGroupingRules(event);

    expect(event.fingerprint).toEqual(['schema-validation', 'SecretActivityResponse']);
  });

  it('produces the SAME group for identical messages with different minified culprits', () => {
    // The deploy-fragmentation case: same defect, two deploys, two bundle
    // hashes. Default grouping keys on the frames and splits them; the
    // explicit rule must not.
    // `culprit` (a server-side Sentry issue field, not part of the outbound
    // SDK `ErrorEvent` type) is deliberately omitted here — the differing
    // minified bundle is represented instead by each frame's own
    // filename/function, which is what the rule must ignore.
    const eventDeployA: ErrorEvent = {
      type: undefined,
      exception: {
        values: [
          {
            type: 'Error',
            value: SCHEMA_MESSAGE,
            stacktrace: { frames: [{ filename: 'main.Ccws7ZEL.js', function: 'x7' }] },
          },
        ],
      },
    };
    const eventDeployB: ErrorEvent = {
      type: undefined,
      exception: {
        values: [
          {
            type: 'Error',
            value: SCHEMA_MESSAGE,
            stacktrace: { frames: [{ filename: 'main.DZXtQ8Fc.js', function: 'q2' }] },
          },
        ],
      },
    };

    applyGroupingRules(eventDeployA);
    applyGroupingRules(eventDeployB);

    expect(eventDeployA.fingerprint).toBeDefined();
    expect(eventDeployA.fingerprint).toEqual(eventDeployB.fingerprint);
  });

  it('reads a standalone message as well as exception values', () => {
    const event: ErrorEvent = {
      type: undefined,
      message: 'Schema validation failed for MembersResponse — 1 issue(s) [(root)]: …',
    };

    applyGroupingRules(event);

    expect(event.fingerprint).toEqual(['schema-validation', 'MembersResponse']);
  });

  it('does not key on issue counts or field paths — only the schema name', () => {
    const oneIssue: ErrorEvent = {
      type: undefined,
      message: 'Schema validation failed for BrandSettings — 1 issue(s) [font_family]: …',
    };
    const threeIssues: ErrorEvent = {
      type: undefined,
      message:
        'Schema validation failed for BrandSettings — 3 issue(s) [corner_style, primary_color, locale]: …',
    };

    applyGroupingRules(oneIssue);
    applyGroupingRules(threeIssues);

    expect(oneIssue.fingerprint).toEqual(threeIssues.fingerprint);
  });

  it('leaves the context-less message family to default grouping', () => {
    // gracefulParse without a context argument emits no "for <SchemaName>"
    // clause — there is no stable name to key on.
    const event: ErrorEvent = {
      type: undefined,
      message: 'Schema validation failed — 1 issue(s) [(root)]: …',
    };

    applyGroupingRules(event);

    expect(event.fingerprint).toBeUndefined();
  });
});

describe('applyGroupingRules — API request errors (Rule B)', () => {
  it('groups by method, parameterized path, and HTTP status', () => {
    const event: ErrorEvent = {
      type: undefined,
      exception: { values: [{ type: 'AxiosError', value: 'Request failed with status code 404' }] },
    };
    const hint: EventHint = {
      originalException: requestError({ url: '/api/v2/secret/abc123', method: 'get', status: 404 }),
    };

    applyGroupingRules(event, hint);

    expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/secret/[REDACTED]', '404']);
  });

  it('produces the SAME group for two different secret identifiers', () => {
    // Two users, two secrets, one broken endpoint: the identifier must be
    // parameterized out by the existing URL scrubbers, never keyed on.
    const idA = 'a'.repeat(62);
    const idB = 'b'.repeat(62);

    const eventA: ErrorEvent = { type: undefined };
    const eventB: ErrorEvent = { type: undefined };
    applyGroupingRules(eventA, {
      originalException: requestError({ url: `/api/v2/secret/${idA}`, method: 'get', status: 404 }),
    });
    applyGroupingRules(eventB, {
      originalException: requestError({ url: `/api/v2/secret/${idB}`, method: 'get', status: 404 }),
    });

    expect(eventA.fingerprint).toBeDefined();
    expect(eventA.fingerprint).toEqual(eventB.fingerprint);
  });

  it('parameterizes receipt endpoints the same way', () => {
    const event: ErrorEvent = { type: undefined };
    applyGroupingRules(event, {
      originalException: requestError({
        url: `/api/v2/receipt/${'c'.repeat(62)}`,
        method: 'post',
        status: 404,
      }),
    });

    expect(event.fingerprint).toEqual(['api-error', 'POST', '/api/v2/receipt/[REDACTED]', '404']);
  });

  it('drops the query string from the grouping path', () => {
    const event: ErrorEvent = { type: undefined };
    applyGroupingRules(event, {
      originalException: requestError({
        url: '/api/v2/status?cb=1755859200',
        method: 'get',
        status: 500,
      }),
    });

    expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/status', '500']);
  });

  it("keys cancelled requests as 'aborted' (axios and fetch vocabularies)", () => {
    for (const shape of [
      { code: 'ERR_CANCELED', name: 'CanceledError' },
      { code: 'ECONNABORTED' },
      { name: 'AbortError' },
    ]) {
      const event: ErrorEvent = { type: undefined };
      applyGroupingRules(event, {
        originalException: requestError({ url: '/api/v2/status', method: 'get', ...shape }),
      });
      expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/status', 'aborted']);
    }
  });

  it("keys no-response failures as 'network'", () => {
    const event: ErrorEvent = { type: undefined };
    applyGroupingRules(event, {
      originalException: requestError({
        url: '/api/v2/status',
        method: 'get',
        code: 'ERR_NETWORK',
        message: 'Network Error',
      }),
    });

    expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/status', 'network']);
  });

  it.each([
    { label: 'axios ETIMEDOUT (clarifyTimeoutError)', shape: { code: 'ETIMEDOUT' } },
    { label: 'fetch AbortSignal.timeout', shape: { name: 'TimeoutError' } },
  ])(
    "keys deadline failures as 'timeout', separate from 'aborted' — $label",
    ({ shape }) => {
      // A timeout is the API failing to answer; an abort is the user leaving.
      // They share code ECONNABORTED on the wire unless the client asks
      // otherwise (src/api/index.ts sets transitional.clarifyTimeoutError),
      // and only this split lets the noise filter drop one without the other.
      const event: ErrorEvent = { type: undefined };
      applyGroupingRules(event, {
        originalException: requestError({ url: '/api/v2/status', method: 'get', ...shape }),
      });

      expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/status', 'timeout']);
    }
  );

  it('falls back to the error class name when there is no status and no known code', () => {
    const event: ErrorEvent = { type: undefined };
    applyGroupingRules(event, {
      originalException: requestError({
        url: '/api/v2/status',
        method: 'get',
        name: 'QuotaExceededError',
      }),
    });

    expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/status', 'QuotaExceededError']);
  });

  it('defaults the method to GET when the config omits it', () => {
    const event: ErrorEvent = { type: undefined };
    applyGroupingRules(event, {
      originalException: requestError({ url: '/api/v2/status', status: 404 }),
    });

    expect(event.fingerprint).toEqual(['api-error', 'GET', '/api/v2/status', '404']);
  });
});

describe('applyGroupingRules — pass-through', () => {
  it('leaves events matching neither rule untouched (default grouping preserved)', () => {
    const event: ErrorEvent = {
      type: undefined,
      exception: {
        values: [
          { type: 'TypeError', value: "Cannot read properties of undefined (reading 'foo')" },
        ],
      },
    };

    applyGroupingRules(event, { originalException: new TypeError('nope') });

    expect(event.fingerprint).toBeUndefined();
  });

  it('respects a grouping array already set upstream', () => {
    const event: ErrorEvent = {
      type: undefined,
      message: SCHEMA_MESSAGE,
      fingerprint: ['custom-upstream-group'],
    };

    applyGroupingRules(event);

    expect(event.fingerprint).toEqual(['custom-upstream-group']);
  });

  it('prefers the schema rule when an event matches both families', () => {
    // A schema failure captured off the back of an API response: the defect
    // is the contract drift, not the transport, so it groups by schema.
    const event: ErrorEvent = { type: undefined, message: SCHEMA_MESSAGE };

    applyGroupingRules(event, {
      originalException: requestError({ url: '/api/v2/secret/abc', method: 'get', status: 200 }),
    });

    expect(event.fingerprint).toEqual(['schema-validation', 'SecretActivityResponse']);
  });

  it('ignores hints whose originalException is not request-shaped', () => {
    for (const originalException of [undefined, null, 'a string', new Error('plain')]) {
      const event: ErrorEvent = { type: undefined };
      applyGroupingRules(event, { originalException } as EventHint);
      expect(event.fingerprint).toBeUndefined();
    }
  });
});

// ---------------------------------------------------------------------------
// beforeSend integration — grouping composes with, and does not replace,
// the existing scrubbing pipeline.
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
        sentry: {
          dsn: 'https://key@sentry.io/123',
          enabled: true,
          logErrors: true,
          trackComponents: true,
          environment: 'test',
          release: '1.0.0',
        },
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

  it('applies grouping AND still runs the existing scrubbers', () => {
    const handler = getBeforeSend();

    // Status 500, not 404: a 404 is expected transport noise (#4286) and is
    // dropped before grouping/scrubbing ever run — see expectedOutcomes.spec.ts.
    // This test's own concern is that grouping composes with the scrubbing
    // pipeline for an event that IS reported, so it needs an outcome that
    // survives the drop filter.
    const event: ErrorEvent = {
      type: undefined,
      exception: {
        values: [
          {
            type: 'AxiosError',
            // An email interpolated into the message must still be scrubbed;
            // grouping composes with the pipeline, it does not replace it.
            value: 'Request failed with status code 500 for user@example.com',
          },
        ],
      },
    };
    const hint: EventHint = {
      originalException: requestError({ url: '/api/v2/secret/abc123', method: 'get', status: 500 }),
    };

    const result = handler(event, hint) as ErrorEvent;

    expect(result.exception?.values?.[0].value).toBe(
      'Request failed with status code 500 for [EMAIL_REDACTED]'
    );
    expect(result.fingerprint).toEqual(['api-error', 'GET', '/api/v2/secret/[REDACTED]', '500']);
  });

  it('leaves non-matching events with default grouping through beforeSend', () => {
    const handler = getBeforeSend();

    const result = handler(
      { type: undefined, exception: { values: [{ type: 'TypeError', value: 'boom' }] } },
      { originalException: new TypeError('boom') }
    ) as ErrorEvent;

    expect(result.fingerprint).toBeUndefined();
  });
});
