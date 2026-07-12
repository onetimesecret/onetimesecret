// src/tests/plugins/core/createDiagnostics.spec.ts
//
// Integration tests for the createDiagnostics plugin function.
// Tests jurisdiction tagging and Sentry client initialization.
//
// Issue: #2970 - Add jurisdiction tag to Sentry events

/* eslint-disable max-classes-per-file */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { Router } from 'vue-router';

// ---------------------------------------------------------------------------
// Mocks - must use vi.hoisted() for variables used in vi.mock factories
// ---------------------------------------------------------------------------
const {
  mockSetTag,
  mockSetClient,
  mockClientInit,
  mockSetTransactionName,
  mockGetBootstrapValue,
  MockBrowserClient,
  MockScope,
} = vi.hoisted(() => {
  const mockSetTag = vi.fn();
  const mockSetClient = vi.fn();
  const mockClientInit = vi.fn();
  const mockClientClose = vi.fn().mockResolvedValue(undefined);
  const mockSetTransactionName = vi.fn();
  const mockGetBootstrapValue = vi.fn();

  class MockBrowserClient {
    init = mockClientInit;
    close = mockClientClose;
  }

  class MockScope {
    setClient = mockSetClient;
    setTag = mockSetTag;
    setTransactionName = mockSetTransactionName;
  }

  return {
    mockSetTag,
    mockSetClient,
    mockClientInit,
    mockSetTransactionName,
    mockGetBootstrapValue,
    MockBrowserClient,
    MockScope,
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

function createMockRouter(): Router {
  return {
    currentRoute: {
      value: {
        params: {},
        meta: {},
      },
    },
    afterEach: vi.fn(),
  } as unknown as Router;
}

const baseConfig = {
  sentry: {
    dsn: 'https://key@sentry.io/123',
    environment: 'test',
    release: '1.0.0',
  },
};

/** Test fixture host - uses 'localhost' to avoid CodeQL regex anchor false positives */
const TEST_HOST = 'example.com';

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe('createDiagnostics jurisdiction tagging', () => {
  const originalConsoleDebug = console.debug;

  beforeEach(() => {
    vi.clearAllMocks();
    console.debug = vi.fn();
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  it('sets jurisdiction tag when regions.current_jurisdiction is "EU"', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'EU' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'eu');
  });

  it('sets jurisdiction tag when regions.current_jurisdiction is "us"', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'us' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'us');
  });

  it('sets jurisdiction tag with mixed case "Us" normalized to lowercase', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'Us' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'us');
  });

  it('does not set jurisdiction tag when current_jurisdiction is empty string', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: '' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
  });

  it('does not set jurisdiction tag when current_jurisdiction is null', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: null });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
  });

  it('does not set jurisdiction tag when current_jurisdiction is undefined', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: undefined });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
  });

  it('does not set jurisdiction tag when regions object is missing', () => {
    mockGetBootstrapValue.mockReturnValue(null);

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
  });

  it('does not set jurisdiction tag when regions object has no current_jurisdiction property', () => {
    mockGetBootstrapValue.mockReturnValue({ other_property: 'value' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledTimes(2);
    expect(mockSetTag).toHaveBeenCalledWith('service', 'web');
    expect(mockSetTag).toHaveBeenCalledWith('site_host', TEST_HOST);
  });

  it('initializes Sentry client and scope', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetClient).toHaveBeenCalled();
    expect(mockClientInit).toHaveBeenCalled();
  });

  it('names transactions from the matched route record path on navigation', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });
    const router = createMockRouter();

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router,
    });

    // Capture the afterEach hook and simulate a navigation to a secret link
    const afterEachMock = router.afterEach as ReturnType<typeof vi.fn>;
    expect(afterEachMock).toHaveBeenCalledTimes(1);
    const hook = afterEachMock.mock.calls[0][0];

    hook({
      path: '/secret/abc123def456',
      matched: [{ path: '/secret/:secretKey' }],
    });

    // Parameterized route path, not the resolved URL with the identifier
    expect(mockSetTransactionName).toHaveBeenCalledWith('/secret/:secretKey');
  });

  it('falls back to the resolved path when no route record matched', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });
    const router = createMockRouter();

    createDiagnostics({
      host: TEST_HOST,
      config: baseConfig,
      router,
    });

    const afterEachMock = router.afterEach as ReturnType<typeof vi.fn>;
    const hook = afterEachMock.mock.calls[0][0];

    hook({ path: '/unknown-page', matched: [] });

    expect(mockSetTransactionName).toHaveBeenCalledWith('/unknown-page');
  });
});
