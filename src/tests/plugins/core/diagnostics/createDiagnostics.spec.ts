// src/tests/plugins/core/createDiagnostics.spec.ts
//
// Integration tests for the createDiagnostics plugin function.
// Tests jurisdiction tagging and Sentry client initialization.
//
// Issue: #2970 - Add jurisdiction tag to Sentry events

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
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

  return {
    mockSetTag,
    mockSetClient,
    mockClientInit,
    mockClientClose,
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
  } as unknown as Router;
}

const baseConfig = {
  sentry: {
    dsn: 'https://key@sentry.io/123',
    environment: 'test',
    release: '1.0.0',
  },
};

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
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'eu');
  });

  it('sets jurisdiction tag when regions.current_jurisdiction is "us"', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'us' });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'us');
  });

  it('sets jurisdiction tag with mixed case "Us" normalized to lowercase', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'Us' });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).toHaveBeenCalledWith('jurisdiction', 'us');
  });

  it('does not set jurisdiction tag when current_jurisdiction is empty string', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: '' });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).not.toHaveBeenCalled();
  });

  it('does not set jurisdiction tag when current_jurisdiction is null', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: null });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).not.toHaveBeenCalled();
  });

  it('does not set jurisdiction tag when current_jurisdiction is undefined', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: undefined });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).not.toHaveBeenCalled();
  });

  it('does not set jurisdiction tag when regions object is missing', () => {
    mockGetBootstrapValue.mockReturnValue(null);

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).not.toHaveBeenCalled();
  });

  it('does not set jurisdiction tag when regions object has no current_jurisdiction property', () => {
    mockGetBootstrapValue.mockReturnValue({ other_property: 'value' });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetTag).not.toHaveBeenCalled();
  });

  it('initializes Sentry client and scope', () => {
    mockGetBootstrapValue.mockReturnValue({ current_jurisdiction: 'eu' });

    createDiagnostics({
      host: 'example.com',
      config: baseConfig,
      router: createMockRouter(),
    });

    expect(mockSetClient).toHaveBeenCalled();
    expect(mockClientInit).toHaveBeenCalled();
  });
});
