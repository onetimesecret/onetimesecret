// src/tests/plugins/core/enableDiagnostics.spec.ts
//
// Tests for the enableDiagnostics plugin (Sentry frontend initialization).
//
// Issue: #2970 - Add jurisdiction tag to Sentry events
//
// This file tests:
// 1. URL scrubbing functions (collectValuesToRedact, scrubUrlWithValues)
// 2. beforeSend handler behavior with route params
// 3. Jurisdiction tagging via createDiagnostics plugin
//
// Run:
//   pnpm test src/tests/plugins/core/enableDiagnostics.spec.ts

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import type { ErrorEvent } from '@sentry/core';

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

  // Create mock classes that can be instantiated with `new`
  class MockBrowserClient {
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

import { __testing, createDiagnostics } from '@/plugins/core/enableDiagnostics';

const { collectValuesToRedact, scrubUrlWithValues, createBeforeSendHandler } = __testing;

// ---------------------------------------------------------------------------
// Unit tests for URL scrubbing functions (via __testing export)
// ---------------------------------------------------------------------------

describe('enableDiagnostics URL scrubbing', () => {
  describe('collectValuesToRedact', () => {
    it('collects all param values when paramsToScrub is undefined', () => {
      const params = { secretKey: 'abc123', identifier: 'xyz789' };
      const result = collectValuesToRedact(params, undefined);

      expect(result).toContain('abc123');
      expect(result).toContain('xyz789');
      expect(result).toHaveLength(2);
    });

    it('collects all param values when paramsToScrub is true', () => {
      const params = { secretKey: 'abc123', identifier: 'xyz789' };
      const result = collectValuesToRedact(params, true);

      expect(result).toContain('abc123');
      expect(result).toContain('xyz789');
    });

    it('collects only specified params when paramsToScrub is an array', () => {
      const params = { secretKey: 'abc123', identifier: 'xyz789', safeParam: 'keep' };
      const result = collectValuesToRedact(params, ['secretKey']);

      expect(result).toContain('abc123');
      expect(result).not.toContain('xyz789');
      expect(result).not.toContain('keep');
    });

    it('handles array param values', () => {
      const params = { ids: ['first', 'second', 'third'] };
      const result = collectValuesToRedact(params, undefined);

      expect(result).toContain('first');
      expect(result).toContain('second');
      expect(result).toContain('third');
    });

    it('sorts values by length descending', () => {
      const params = { short: 'ab', medium: 'abcde', long: 'abcdefghij' };
      const result = collectValuesToRedact(params, undefined);

      expect(result[0]).toBe('abcdefghij');
      expect(result[1]).toBe('abcde');
      expect(result[2]).toBe('ab');
    });

    it('deduplicates identical values', () => {
      const params = { key1: 'same', key2: 'same' };
      const result = collectValuesToRedact(params, undefined);

      expect(result).toHaveLength(1);
      expect(result[0]).toBe('same');
    });

    it('skips empty string values', () => {
      const params = { empty: '', valid: 'value' };
      const result = collectValuesToRedact(params, undefined);

      expect(result).toHaveLength(1);
      expect(result[0]).toBe('value');
    });
  });

  describe('scrubUrlWithValues', () => {
    it('replaces param values in URL path', () => {
      const url = 'https://example.com/secret/abc123xyz';
      const values = ['abc123xyz'];
      const result = scrubUrlWithValues(url, values);

      expect(result).toBe('https://example.com/secret/[REDACTED]');
    });

    it('replaces param values in query string', () => {
      const url = 'https://example.com/page?token=secret123&other=keep';
      const values = ['secret123'];
      const result = scrubUrlWithValues(url, values);

      expect(result).toBe('https://example.com/page?token=[REDACTED]&other=keep');
    });

    it('replaces param values in hash fragment', () => {
      const url = 'https://example.com/page#section/mysecret';
      const values = ['mysecret'];
      const result = scrubUrlWithValues(url, values);

      expect(result).toBe('https://example.com/page#section/[REDACTED]');
    });

    it('does not modify origin/hostname', () => {
      // This tests the protection against accidental hostname redaction
      const url = 'https://onetimesecret.com/secret/one';
      const values = ['one']; // 'one' appears in hostname
      const result = scrubUrlWithValues(url, values);

      // Should only redact in path, not in hostname
      expect(result).toBe('https://onetimesecret.com/secret/[REDACTED]');
    });

    it('replaces longer values before shorter to avoid corruption', () => {
      const url = 'https://example.com/secret/foobar/foo';
      const values = ['foobar', 'foo']; // Already sorted by length
      const result = scrubUrlWithValues(url, values);

      // 'foobar' should be replaced first, then 'foo'
      expect(result).toBe('https://example.com/secret/[REDACTED]/[REDACTED]');
    });

    it('handles relative URLs gracefully', () => {
      const url = '/secret/abc123';
      const values = ['abc123'];
      const result = scrubUrlWithValues(url, values);

      expect(result).toBe('/secret/[REDACTED]');
    });

    it('returns original URL when values array is empty', () => {
      const url = 'https://example.com/secret/abc123';
      const result = scrubUrlWithValues(url, []);

      expect(result).toBe(url);
    });

    it('returns original URL when URL is empty', () => {
      const result = scrubUrlWithValues('', ['value']);

      expect(result).toBe('');
    });

    it('handles multiple occurrences of the same value', () => {
      const url = 'https://example.com/secret/abc123/receipt/abc123';
      const values = ['abc123'];
      const result = scrubUrlWithValues(url, values);

      expect(result).toBe('https://example.com/secret/[REDACTED]/receipt/[REDACTED]');
    });
  });
});

// ---------------------------------------------------------------------------
// Tests for beforeSend handler (using real production function)
// ---------------------------------------------------------------------------

describe('createBeforeSendHandler', () => {
  const originalConsoleDebug = console.debug;

  beforeEach(() => {
    vi.clearAllMocks();
    console.debug = vi.fn();
  });

  afterEach(() => {
    console.debug = originalConsoleDebug;
  });

  function createMockRouter(params: Record<string, string | string[]>, meta: Record<string, unknown> = {}) {
    return {
      currentRoute: {
        value: {
          params,
          meta,
        },
      },
    } as unknown as import('vue-router').Router;
  }

  it('removes secret property from events', () => {
    const mockRouter = createMockRouter({});
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = { secret: 'should-be-removed', message: 'test' } as unknown as ErrorEvent;
    const result = beforeSend(event);

    expect(result).not.toHaveProperty('secret');
    expect(result).toHaveProperty('message', 'test');
  });

  it('skips scrubbing when sentryScrubParams is false', () => {
    const mockRouter = createMockRouter(
      { secretKey: 'mysecret123' },
      { sentryScrubParams: false }
    );
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = {
      request: { url: 'https://example.com/secret/mysecret123' },
    } as ErrorEvent;
    const result = beforeSend(event);

    expect(result?.request?.url).toBe('https://example.com/secret/mysecret123');
  });

  it('scrubs all params by default (sentryScrubParams undefined)', () => {
    const mockRouter = createMockRouter({ secretKey: 'abc123' });
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = {
      request: { url: 'https://example.com/secret/abc123' },
    } as ErrorEvent;
    const result = beforeSend(event);

    expect(result?.request?.url).toBe('https://example.com/secret/[REDACTED]');
  });

  it('scrubs only specified params when sentryScrubParams is an array', () => {
    const mockRouter = createMockRouter(
      { secretKey: 'secret123', publicId: 'public456' },
      { sentryScrubParams: ['secretKey'] }
    );
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = {
      request: { url: 'https://example.com/secret123/info/public456' },
    } as ErrorEvent;
    const result = beforeSend(event);

    // Only secretKey value should be scrubbed
    expect(result?.request?.url).toBe('https://example.com/[REDACTED]/info/public456');
  });

  it('scrubs transaction name', () => {
    const mockRouter = createMockRouter({ identifier: 'txn123' });
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = {
      transaction: '/secret/txn123',
    } as ErrorEvent;
    const result = beforeSend(event);

    expect(result?.transaction).toBe('/secret/[REDACTED]');
  });

  it('scrubs breadcrumb URLs', () => {
    const mockRouter = createMockRouter({ secretKey: 'bread123' });
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = {
      breadcrumbs: [
        { data: { url: 'https://example.com/secret/bread123' } },
        { data: { to: '/secret/bread123', from: '/home' } },
      ],
    } as ErrorEvent;
    const result = beforeSend(event);

    expect(result?.breadcrumbs?.[0].data?.url).toBe('https://example.com/secret/[REDACTED]');
    expect(result?.breadcrumbs?.[1].data?.to).toBe('/secret/[REDACTED]');
    expect(result?.breadcrumbs?.[1].data?.from).toBe('/home');
  });

  it('returns event unchanged when no params present', () => {
    const mockRouter = createMockRouter({});
    const beforeSend = createBeforeSendHandler(mockRouter);

    const event = {
      request: { url: 'https://example.com/about' },
    } as ErrorEvent;
    const result = beforeSend(event);

    expect(result?.request?.url).toBe('https://example.com/about');
  });
});

// ---------------------------------------------------------------------------
// Tests for jurisdiction tagging (calling real createDiagnostics)
// ---------------------------------------------------------------------------

describe('createDiagnostics jurisdiction tagging', () => {
  const originalConsoleDebug = console.debug;

  function createMockRouter() {
    return {
      currentRoute: {
        value: {
          params: {},
          meta: {},
        },
      },
    } as unknown as import('vue-router').Router;
  }

  const baseConfig = {
    sentry: {
      dsn: 'https://key@sentry.io/123',
      environment: 'test',
      release: '1.0.0',
    },
  };

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
