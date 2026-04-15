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

    it('handles non-string path values gracefully', () => {
      const handler = getBeforeBreadcrumb();
      const breadcrumb: Breadcrumb = {
        category: 'navigation',
        data: {
          from: null,
          to: 123,
        },
      };

      const result = handler(breadcrumb);

      expect(result?.data?.from).toBe(null);
      expect(result?.data?.to).toBe(123);
    });
  });
});
