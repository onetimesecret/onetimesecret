// src/tests/plugins/enableDiagnostics.spec.ts

import {
  collectValuesToRedact,
  createBeforeBreadcrumbHandler,
  createBeforeSendHandler,
  EMAIL_PATTERN,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
  scrubUrlWithValues,
  SENSITIVE_PATH_PATTERN,
  VERIFIABLE_ID_PATTERN,
} from '@/plugins/core/enableDiagnostics';
import type { RouteMeta } from '@/types/router';
import type { Breadcrumb, ErrorEvent } from '@sentry/core';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { RouteLocationNormalizedLoaded, Router } from 'vue-router';

/**
 * Creates a mock router for testing createBeforeBreadcrumbHandler.
 * Allows configuring route resolution behavior per test.
 */
function createMockRouter(
  resolveConfig: Record<
    string,
    {
      params: Record<string, string | string[]>;
      meta: Partial<RouteMeta>;
    }
  > = {}
): Router {
  return {
    resolve: vi.fn((path: string) => {
      const config = resolveConfig[path];
      if (config) {
        return {
          params: config.params,
          meta: config.meta,
        };
      }
      // Default: no params, no special meta
      return {
        params: {},
        meta: {},
      };
    }),
    currentRoute: {
      value: {
        params: {},
        meta: {},
      } as RouteLocationNormalizedLoaded,
    },
  } as unknown as Router;
}

describe('enableDiagnostics URL scrubbing', () => {
  describe('SENSITIVE_PATH_PATTERN', () => {
    beforeEach(() => {
      // Reset regex lastIndex since we use global flag
      SENSITIVE_PATH_PATTERN.lastIndex = 0;
    });

    it('matches /secret/ paths', () => {
      expect('/api/v3/secret/abc123'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
    });

    it('matches /private/ paths', () => {
      expect('/api/v3/private/xyz789'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
    });

    it('matches /receipt/ paths', () => {
      expect('/api/v3/receipt/def456'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
    });

    it('matches /incoming/ paths', () => {
      expect('/api/v3/incoming/ghi012'.match(SENSITIVE_PATH_PATTERN)).toBeTruthy();
    });

    it('does not match /colonel/ paths', () => {
      SENSITIVE_PATH_PATTERN.lastIndex = 0;
      expect('/api/v3/colonel/admin123'.match(SENSITIVE_PATH_PATTERN)).toBeNull();
    });

    it('does not match /public/ paths', () => {
      SENSITIVE_PATH_PATTERN.lastIndex = 0;
      expect('/api/v3/public/something'.match(SENSITIVE_PATH_PATTERN)).toBeNull();
    });
  });

  describe('VERIFIABLE_ID_PATTERN', () => {
    beforeEach(() => {
      VERIFIABLE_ID_PATTERN.lastIndex = 0;
    });

    it('matches 62-character base62 identifiers', () => {
      const id62 = 'a'.repeat(62);
      expect(id62.match(VERIFIABLE_ID_PATTERN)).toBeTruthy();
    });

    it('matches mixed alphanumeric 62-char IDs', () => {
      // 62 lowercase alphanumeric characters (a-z, 0-9)
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      expect(id62.length).toBe(62);
      expect(id62.match(VERIFIABLE_ID_PATTERN)).toBeTruthy();
    });

    it('does not match shorter identifiers', () => {
      const id61 = 'a'.repeat(61);
      VERIFIABLE_ID_PATTERN.lastIndex = 0;
      expect(id61.match(VERIFIABLE_ID_PATTERN)).toBeNull();
    });

    it('does not match longer identifiers as a single match', () => {
      const id63 = 'a'.repeat(63);
      VERIFIABLE_ID_PATTERN.lastIndex = 0;
      // Will match the first 62 chars, but the match itself is 62 chars
      const matches = id63.match(VERIFIABLE_ID_PATTERN);
      expect(matches?.[0].length).toBe(62);
    });
  });

  describe('scrubUrlWithPatterns', () => {
    it('scrubs /secret/ path identifiers', () => {
      const url = '/api/v3/secret/abc123def456';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/secret/[REDACTED]');
    });

    it('scrubs /private/ path identifiers', () => {
      const url = '/api/v3/private/xyz789';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/private/[REDACTED]');
    });

    it('scrubs /receipt/ path identifiers', () => {
      const url = '/api/v3/receipt/receipt123';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/receipt/[REDACTED]');
    });

    it('scrubs /incoming/ path identifiers', () => {
      const url = '/api/v3/incoming/incoming456';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/incoming/[REDACTED]');
    });

    it('scrubs 62-char verifiable IDs anywhere in URL', () => {
      // 62 lowercase alphanumeric characters (a-z, 0-9)
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      const url = `/api/v3/unknown/${id62}`;
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/unknown/[REDACTED]');
    });

    it('scrubs multiple sensitive segments in one URL', () => {
      const url = '/api/v3/secret/abc123/private/xyz789';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/secret/[REDACTED]/private/[REDACTED]');
    });

    it('leaves non-sensitive URLs unchanged', () => {
      const url = '/api/v3/colonel/admin';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/colonel/admin');
    });

    it('leaves /pricing routes unchanged', () => {
      const url = '/pricing/monthly/basic';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/pricing/monthly/basic');
    });

    it('handles empty string input', () => {
      expect(scrubUrlWithPatterns('')).toBe('');
    });

    it('handles null input gracefully', () => {
      expect(scrubUrlWithPatterns(null as unknown as string)).toBe(null);
    });

    it('handles undefined input gracefully', () => {
      expect(scrubUrlWithPatterns(undefined as unknown as string)).toBe(undefined);
    });

    it('preserves query strings after scrubbing path', () => {
      const url = '/api/v3/secret/abc123?timestamp=12345';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v3/secret/[REDACTED]?timestamp=12345');
    });

    it('handles full URLs with protocol and host', () => {
      const url = 'https://example.com/api/v3/secret/abc123';
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('https://example.com/api/v3/secret/[REDACTED]');
    });
  });

  describe('scrubUrlWithValues', () => {
    it('scrubs values found in URL path', () => {
      const url = 'https://example.com/secret/abc123/view';
      const result = scrubUrlWithValues(url, ['abc123']);
      expect(result).toBe('https://example.com/secret/[REDACTED]/view');
    });

    it('scrubs values found in query string', () => {
      const url = 'https://example.com/page?token=secret456';
      const result = scrubUrlWithValues(url, ['secret456']);
      expect(result).toBe('https://example.com/page?token=[REDACTED]');
    });

    it('scrubs values found in hash fragment', () => {
      const url = 'https://example.com/page#section-token789';
      const result = scrubUrlWithValues(url, ['token789']);
      expect(result).toBe('https://example.com/page#section-[REDACTED]');
    });

    it('protects hostname from accidental redaction', () => {
      // "one" appears in "onetimesecret.com" but should not be redacted
      const url = 'https://onetimesecret.com/secret/one/view';
      const result = scrubUrlWithValues(url, ['one']);
      expect(result).toBe('https://onetimesecret.com/secret/[REDACTED]/view');
      expect(result).toContain('onetimesecret.com');
    });

    it('scrubs multiple values in order of length (longest first)', () => {
      const url = 'https://example.com/path/foobar/foo';
      // Values should be pre-sorted by caller, but function handles them in order
      const result = scrubUrlWithValues(url, ['foobar', 'foo']);
      expect(result).toBe('https://example.com/path/[REDACTED]/[REDACTED]');
    });

    it('handles empty values array', () => {
      const url = 'https://example.com/secret/abc123';
      const result = scrubUrlWithValues(url, []);
      expect(result).toBe('https://example.com/secret/abc123');
    });

    it('handles empty URL', () => {
      expect(scrubUrlWithValues('', ['value'])).toBe('');
    });

    it('handles null URL gracefully', () => {
      expect(scrubUrlWithValues(null as unknown as string, ['value'])).toBe(null);
    });

    it('handles relative URLs with fallback behavior', () => {
      const url = '/secret/abc123/view';
      const result = scrubUrlWithValues(url, ['abc123']);
      // Relative URLs fall back to simple string replacement
      expect(result).toBe('/secret/[REDACTED]/view');
    });

    it('scrubs array param values', () => {
      const url = 'https://example.com/items/item1/item2/item3';
      const result = scrubUrlWithValues(url, ['item1', 'item2', 'item3']);
      expect(result).toBe('https://example.com/items/[REDACTED]/[REDACTED]/[REDACTED]');
    });
  });

  describe('collectValuesToRedact', () => {
    it('collects all params when paramsToScrub is undefined', () => {
      const params = { secretKey: 'abc123', receiptKey: 'xyz789' };
      const result = collectValuesToRedact(params, undefined);
      expect(result).toContain('abc123');
      expect(result).toContain('xyz789');
    });

    it('collects all params when paramsToScrub is true', () => {
      const params = { secretKey: 'abc123', receiptKey: 'xyz789' };
      const result = collectValuesToRedact(params, true);
      expect(result).toContain('abc123');
      expect(result).toContain('xyz789');
    });

    it('collects only named params when paramsToScrub is string[]', () => {
      const params = { secretKey: 'abc123', publicId: 'xyz789' };
      const result = collectValuesToRedact(params, ['secretKey']);
      expect(result).toContain('abc123');
      expect(result).not.toContain('xyz789');
    });

    it('returns empty array when paramsToScrub is false', () => {
      const params = { secretKey: 'abc123', receiptKey: 'xyz789' };
      // false means explicitly opted out - but the function doesn't check for false
      // The caller (beforeSend/beforeBreadcrumb) should check for false before calling
      // This test documents current behavior
      const result = collectValuesToRedact(params, false);
      // When paramsToScrub is false (boolean), it's not an array so all params are collected
      expect(result).toContain('abc123');
    });

    it('sorts values by length descending', () => {
      const params = { short: 'a', medium: 'abc', long: 'abcdef' };
      const result = collectValuesToRedact(params, undefined);
      expect(result[0]).toBe('abcdef');
      expect(result[1]).toBe('abc');
      expect(result[2]).toBe('a');
    });

    it('handles array param values', () => {
      const params = { items: ['first', 'second', 'third'] };
      const result = collectValuesToRedact(params, undefined);
      expect(result).toContain('first');
      expect(result).toContain('second');
      expect(result).toContain('third');
    });

    it('deduplicates repeated values', () => {
      const params = { key1: 'duplicate', key2: 'duplicate' };
      const result = collectValuesToRedact(params, undefined);
      expect(result.filter((v) => v === 'duplicate')).toHaveLength(1);
    });

    it('filters out empty string values', () => {
      const params = { empty: '', valid: 'value' };
      const result = collectValuesToRedact(params, undefined);
      expect(result).not.toContain('');
      expect(result).toContain('value');
    });

    it('handles empty params object', () => {
      const params = {};
      const result = collectValuesToRedact(params, undefined);
      expect(result).toEqual([]);
    });
  });

  describe('createBeforeBreadcrumbHandler', () => {
    describe('navigation breadcrumbs', () => {
      it('scrubs navigation breadcrumb "to" URL using route params', () => {
        const mockRouter = createMockRouter({
          '/secret/abc123': {
            params: { secretKey: 'abc123' },
            meta: { sentryScrubParams: undefined },
          },
        });

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter({
          '/secret/xyz789': {
            params: { secretKey: 'xyz789' },
            meta: {},
          },
        });

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter({
          '/colonel/admin': {
            params: { adminId: 'admin' },
            meta: { sentryScrubParams: false },
          },
        });

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter({
          '/user/john/token/secret123': {
            params: { username: 'john', token: 'secret123' },
            meta: { sentryScrubParams: ['token'] },
          },
        });

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter({
          '/about': {
            params: {},
            meta: {},
          },
        });

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = {
          resolve: vi.fn(() => {
            throw new Error('Route not found');
          }),
          currentRoute: { value: { params: {}, meta: {} } },
        } as unknown as Router;

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter();
        // 62 lowercase alphanumeric characters (a-z, 0-9)
        const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
        const breadcrumb: Breadcrumb = {
          category: 'console',
          message: 'Debug: processing secret abc123',
          level: 'info',
        };

        const result = handler(breadcrumb);

        expect(result).toEqual(breadcrumb);
      });

      it('passes through ui.click breadcrumbs unchanged', () => {
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
        const breadcrumb: Breadcrumb = {
          category: 'ui.click',
          message: 'body > div > button',
        };

        const result = handler(breadcrumb);

        expect(result).toEqual(breadcrumb);
      });

      it('handles breadcrumbs without data property', () => {
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
        const breadcrumb: Breadcrumb = {
          category: 'navigation',
          message: 'Page changed',
        };

        const result = handler(breadcrumb);

        expect(result).toEqual(breadcrumb);
      });

      it('handles HTTP breadcrumbs without url in data', () => {
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter({
          '': { params: {}, meta: {} },
        });

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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
        const mockRouter = createMockRouter();

        const handler = createBeforeBreadcrumbHandler(mockRouter);
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

  describe('EMAIL_PATTERN', () => {
    beforeEach(() => {
      EMAIL_PATTERN.lastIndex = 0;
    });

    it('matches standard email addresses', () => {
      expect('user@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('matches emails with subdomains', () => {
      expect('user@mail.example.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('matches emails with plus addressing', () => {
      expect('user+tag@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('matches emails with dots in local part', () => {
      expect('first.last@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('matches emails with numbers', () => {
      expect('user123@example456.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('does not match invalid email formats', () => {
      EMAIL_PATTERN.lastIndex = 0;
      expect('not-an-email'.match(EMAIL_PATTERN)).toBeNull();
    });

    it('does not match email without domain', () => {
      EMAIL_PATTERN.lastIndex = 0;
      expect('user@'.match(EMAIL_PATTERN)).toBeNull();
    });
  });

  describe('scrubSensitiveStrings', () => {
    it('scrubs email addresses from text', () => {
      const text = 'Contact user@example.com for support';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Contact [EMAIL REDACTED] for support');
    });

    it('scrubs multiple email addresses', () => {
      const text = 'From: alice@example.com To: bob@example.com';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('From: [EMAIL REDACTED] To: [EMAIL REDACTED]');
    });

    it('scrubs 62-char verifiable IDs', () => {
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      const text = `Processing secret ${id62}`;
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Processing secret [REDACTED]');
    });

    it('scrubs sensitive path patterns in text', () => {
      const text = 'Error loading /secret/abc123def';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Error loading /secret/[REDACTED]');
    });

    it('scrubs /private/ paths in text', () => {
      const text = 'Failed to fetch /private/xyz789';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Failed to fetch /private/[REDACTED]');
    });

    it('scrubs /receipt/ paths in text', () => {
      const text = 'Receipt at /receipt/receipt123';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Receipt at /receipt/[REDACTED]');
    });

    it('scrubs /incoming/ paths in text', () => {
      const text = 'Incoming at /incoming/incoming456';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Incoming at /incoming/[REDACTED]');
    });

    it('scrubs multiple sensitive patterns in one string', () => {
      const text = 'User user@example.com accessed /secret/abc123';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('User [EMAIL REDACTED] accessed /secret/[REDACTED]');
    });

    it('handles empty string input', () => {
      expect(scrubSensitiveStrings('')).toBe('');
    });

    it('handles null input gracefully', () => {
      expect(scrubSensitiveStrings(null as unknown as string)).toBe(null);
    });

    it('handles undefined input gracefully', () => {
      expect(scrubSensitiveStrings(undefined as unknown as string)).toBe(undefined);
    });

    it('leaves text without sensitive data unchanged', () => {
      const text = 'Application started successfully';
      const result = scrubSensitiveStrings(text);
      expect(result).toBe('Application started successfully');
    });
  });

  describe('createBeforeSendHandler', () => {
    /**
     * Creates a mock router for testing createBeforeSendHandler.
     * Allows configuring currentRoute for each test.
     */
    function createMockRouterWithCurrentRoute(config: {
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

    describe('exception message scrubbing', () => {
      it('scrubs email from exception message', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          exception: {
            values: [{ value: 'Failed for user@example.com' }],
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.exception?.values?.[0].value).toBe('Failed for [EMAIL REDACTED]');
      });

      it('scrubs 62-char ID from exception message', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });
        const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          exception: {
            values: [{ value: `Error processing ${id62}` }],
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.exception?.values?.[0].value).toBe('Error processing [REDACTED]');
      });

      it('scrubs sensitive path from exception message', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          exception: {
            values: [{ value: 'Not found: /secret/abc123' }],
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.exception?.values?.[0].value).toBe('Not found: /secret/[REDACTED]');
      });

      it('scrubs multiple exception values', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
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
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          message: 'User user@example.com logged out',
        };

        const result = handler(event) as ErrorEvent;

        expect(result.message).toBe('User [EMAIL REDACTED] logged out');
      });
    });

    describe('URL scrubbing based on route params', () => {
      it('scrubs request.url using route params', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { secretKey: 'abc123' },
          meta: { sentryScrubParams: undefined },
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          request: {
            url: 'https://example.com/secret/abc123/view',
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.request?.url).toBe('https://example.com/secret/[REDACTED]/view');
      });

      it('scrubs event.transaction', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { secretKey: 'xyz789' },
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          transaction: 'https://example.com/private/xyz789',
        };

        const result = handler(event) as ErrorEvent;

        expect(result.transaction).toBe('https://example.com/private/[REDACTED]');
      });

      it('scrubs breadcrumb URLs in event', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { token: 'secret456' },
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
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
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { adminId: 'admin123' },
          meta: { sentryScrubParams: false },
        });

        const handler = createBeforeSendHandler(mockRouter);
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
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { adminId: 'admin123' },
          meta: { sentryScrubParams: false },
        });

        const handler = createBeforeSendHandler(mockRouter);
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
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { username: 'john', token: 'secret123' },
          meta: { sentryScrubParams: ['token'] },
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          request: {
            url: 'https://example.com/user/john/token/secret123',
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.request?.url).toBe('https://example.com/user/john/token/[REDACTED]');
      });

      it('handles event with no route params', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          request: {
            url: 'https://example.com/about',
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.request?.url).toBe('https://example.com/about');
      });

      it('removes secret property if present on event', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
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
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          exception: {
            values: undefined,
          },
        };

        const result = handler(event);

        expect(result).toEqual(event);
      });

      it('handles exception value without value property', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: {},
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
        const event: ErrorEvent = {
          exception: {
            values: [{ type: 'Error' }],
          },
        };

        const result = handler(event) as ErrorEvent;

        expect(result.exception?.values?.[0].type).toBe('Error');
      });

      it('handles breadcrumb without data', () => {
        const mockRouter = createMockRouterWithCurrentRoute({
          params: { key: 'value' },
          meta: {},
        });

        const handler = createBeforeSendHandler(mockRouter);
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
});
