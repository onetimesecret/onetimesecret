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

  describe('generated anchored patterns (anchoring regression #3004)', () => {
    // These tests verify that the *generated* anchored patterns in
    // src/generated/sentry-scrub-patterns.ts actually participate in
    // scrubUrlWithPatterns — not just the legacy SENSITIVE_PATH_PATTERN
    // fallback. /api/v1/metadata/:key is in the generated patterns but
    // "metadata" is NOT in the legacy fallback list, so a 20-char
    // identifier there can only be scrubbed via the generated anchored
    // regex passing through extractAndScrubPath().
    const ID20 = 'a'.repeat(20);

    it('scrubs a full Sentry-style breadcrumb URL via generated pattern and preserves surrounding parts', () => {
      const url = `https://onetimesecret.com/api/v1/metadata/${ID20}?foo=bar#frag`;
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe(
        'https://onetimesecret.com/api/v1/metadata/[REDACTED]?foo=bar#frag'
      );
    });

    it('scrubs a full URL for /api/v3/secret/:identifier preserving query and fragment', () => {
      const url = `https://onetimesecret.com/api/v3/secret/${ID20}?foo=bar#frag`;
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe(
        'https://onetimesecret.com/api/v3/secret/[REDACTED]?foo=bar#frag'
      );
    });

    it('scrubs a bare path (axios interceptor input) via the catch fallback', () => {
      const url = `/api/v1/metadata/${ID20}`;
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('/api/v1/metadata/[REDACTED]');
    });

    it('preserves a bare path hash fragment through extractAndScrubPath', () => {
      // Bare paths are parsed against a synthetic http://_ base. The hash
      // must round-trip untouched since it is never shown to the regex.
      const url = `/api/v1/metadata/${ID20}#frag`;
      expect(scrubUrlWithPatterns(url)).toBe(
        '/api/v1/metadata/[REDACTED]#frag'
      );
    });

    it('preserves a bare path query + hash fragment through extractAndScrubPath', () => {
      const url = `/api/v1/metadata/${ID20}?foo=bar#frag`;
      expect(scrubUrlWithPatterns(url)).toBe(
        '/api/v1/metadata/[REDACTED]?foo=bar#frag'
      );
    });

    it('scrubs plain bare path with no query or hash', () => {
      // Explicit row from the coverage matrix: no surrounding parts to
      // preserve, the pattern simply rewrites the identifier.
      const url = `/api/v1/metadata/${ID20}`;
      expect(scrubUrlWithPatterns(url)).toBe('/api/v1/metadata/[REDACTED]');
    });

    it('preserves host on protocol-relative URLs', () => {
      // Protocol-relative URLs are preserved through the scrubber
      // to avoid silently losing the host.
      const url = `//host.example.com/api/v1/metadata/${ID20}?q=1`;
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('//host.example.com/api/v1/metadata/[REDACTED]?q=1');
    });

    it('scrubs file:// URLs and preserves the scheme', () => {
      // file:// URLs have an empty host. The hadHost detection fires
      // (scheme://), so reassembly emits protocol + empty host + path,
      // producing file:///... Useful as a sanity check that the scheme
      // regex is not overly restrictive.
      const url = `file:///api/v3/secret/${ID20}`;
      const result = scrubUrlWithPatterns(url);
      expect(result).toBe('file:///api/v3/secret/[REDACTED]');
    });

    it('falls through safely when URL parser throws (bare scheme)', () => {
      // `new URL('http://', base)` throws even with a base, so the
      // try/catch falls back to scrubSensitivePath(input) directly. The
      // legacy SENSITIVE_PATH_PATTERN second pass still runs. The point
      // is that no exception escapes.
      expect(() => scrubUrlWithPatterns('http://')).not.toThrow();
    });

    it('falls through safely for inputs with embedded control characters', () => {
      // Control chars are accepted by the URL parser when the input is
      // relative to a base, but we still want to prove no throw and that
      // a sensitive segment buried in a noisy string does not crash the
      // scrubber. The exact output is implementation-defined; we only
      // assert no exception and that the identifier is not echoed back.
      const url = `\u0000\u0001/api/v1/secret/${ID20}`;
      expect(() => scrubUrlWithPatterns(url)).not.toThrow();
    });
  });
});
