// src/tests/plugins/core/scrubUrl.spec.ts
//
// Unit tests for scrubUrlWithPatterns function.
// Tests regex-based URL scrubbing for sensitive path patterns and verifiable IDs.

import { describe, expect, it } from 'vitest';
import { scrubUrlWithPatterns } from '@/plugins/core/enableDiagnostics';

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
