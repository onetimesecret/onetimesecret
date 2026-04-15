// src/tests/plugins/core/diagnostics/urlScrubbing.spec.ts
//
// Unit tests for internal URL scrubbing utilities.
// These test edge cases directly without Sentry mock infrastructure.
//
// Import from internal path (not the barrel) — see urlScrubbing.ts header for rationale.

import { describe, expect, it } from 'vitest';
import {
  collectValuesToRedact,
  scrubUrlWithValues,
} from '@/plugins/core/diagnostics/urlScrubbing';

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

  it('collects all params when paramsToScrub is false (caller must check)', () => {
    // false means explicitly opted out - but the function doesn't check for false
    // The caller (beforeSend/beforeBreadcrumb) should check for false before calling
    // This test documents the current behavior
    const params = { secretKey: 'abc123', receiptKey: 'xyz789' };
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

  it('handles multiple occurrences of the same value', () => {
    const url = 'https://example.com/secret/abc123/receipt/abc123';
    const result = scrubUrlWithValues(url, ['abc123']);
    expect(result).toBe('https://example.com/secret/[REDACTED]/receipt/[REDACTED]');
  });
});
