// src/tests/plugins/core/beforeSend.spec.ts
//
// Tests for the beforeSend handler created by createDiagnostics.
// Tests exception message scrubbing, URL scrubbing based on route params,
// standalone message scrubbing, and edge cases.
//
// The handler is accessed by calling createDiagnostics() and extracting
// beforeSend from the captured BrowserClient constructor options.

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { ErrorEvent } from '@sentry/core';
import type { Router, RouteLocationNormalizedLoaded } from 'vue-router';
import type { RouteMeta } from '@/types/router';

// ---------------------------------------------------------------------------
// Mocks - must use vi.hoisted() for variables used in vi.mock factories
// ---------------------------------------------------------------------------

const {
  mockSetTag,
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
    mockSetTag,
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
}): Router {
  return {
    resolve: vi.fn(),
    currentRoute: {
      value: {
        params: config.params,
        meta: config.meta,
      } as RouteLocationNormalizedLoaded,
    },
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
function setupWithRouter(routerConfig: { params: Record<string, string | string[]>; meta: Partial<RouteMeta> }): void {
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

      expect(result.exception?.values?.[0].value).toBe('Failed for [EMAIL REDACTED]');
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

      expect(result.exception?.values?.[0].value).toBe('Error for [EMAIL REDACTED]');
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

      expect(result.message).toBe('User [EMAIL REDACTED] logged out');
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
      expect(result.exception?.values?.[0].value).toBe('Error for [EMAIL REDACTED]');
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
