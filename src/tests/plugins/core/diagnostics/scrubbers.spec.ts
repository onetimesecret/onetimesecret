// src/tests/plugins/core/diagnostics/scrubbers.spec.ts
//
// Tests for the scrubbing utilities in the dependency-free scrubbers module.
//
// Run:
//   pnpm test src/tests/plugins/core/diagnostics/scrubbers.spec.ts

import { describe, it, expect } from 'vitest';
import {
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
  scrubSensitiveQueryParams,
  scrubQueryStringValues,
  EMAIL_PATTERN,
  SENSITIVE_PATH_PATTERN,
  SENSITIVE_QUERY_PARAMS,
  VERIFIABLE_ID_PATTERN,
} from '@/plugins/core/diagnostics/scrubbers';

// ---------------------------------------------------------------------------
// C1 shared identifier test-vector set.
//
// One canonical set of verifiable-identifier vectors, exercised by the pattern
// and scrubber tests below. The frontend pattern is
//   /\b(?:[0-9a-z]{62}|[0-9a-z]{31})\b/gi   (case-INSENSITIVE, by design)
// mirroring the backend IDENTIFIER_TEXT_PATTERN
//   /\b(?:[0-9a-z]{62}|[0-9a-z]{31})\b/     (case-SENSITIVE)
// with the deliberate, documented case divergence. Lengths and `\b` anchoring
// are shared.
// ---------------------------------------------------------------------------
const ID_VECTORS = {
  id62: 'a'.repeat(62), // current (v0.24) — redacted
  id31: 'b'.repeat(31), // legacy (v0.23) — redacted
  id62mixed: 'A1b2C3'.padEnd(62, 'z'), // case-insensitive frontend — redacted
  traceId32: 'c'.repeat(32), // ops-useful — survives
  commitHash40: 'd'.repeat(40), // ops-useful — survives
  short6: 'abc123', // too short — survives
} as const;

describe('scrubbers', () => {
  describe('scrubSensitiveStrings', () => {
    it('scrubs email addresses', () => {
      const text = 'User user@example.com reported an error';
      expect(scrubSensitiveStrings(text)).toBe(
        'User [EMAIL_REDACTED] reported an error'
      );
    });

    it('scrubs multiple email addresses', () => {
      const text = 'From: alice@example.com To: bob@test.org';
      expect(scrubSensitiveStrings(text)).toBe(
        'From: [EMAIL_REDACTED] To: [EMAIL_REDACTED]'
      );
    });

    it('scrubs 62-char verifiable IDs', () => {
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      const text = `Secret ID: ${id62}`;
      expect(scrubSensitiveStrings(text)).toBe('Secret ID: [REDACTED]');
    });

    it('scrubs sensitive path patterns', () => {
      const text = 'Error at /secret/abc123 endpoint';
      expect(scrubSensitiveStrings(text)).toBe(
        'Error at /secret/[REDACTED] endpoint'
      );
    });

    it('handles null/undefined gracefully', () => {
      expect(scrubSensitiveStrings(null as unknown as string)).toBe(null);
      expect(scrubSensitiveStrings(undefined as unknown as string)).toBe(undefined);
    });

    it('handles empty string', () => {
      expect(scrubSensitiveStrings('')).toBe('');
    });
  });

  describe('scrubUrlWithPatterns', () => {
    it('scrubs sensitive path patterns', () => {
      expect(scrubUrlWithPatterns('/api/v3/secret/abc123')).toBe(
        '/api/v3/secret/[REDACTED]'
      );
      expect(scrubUrlWithPatterns('/api/v3/private/xyz789')).toBe(
        '/api/v3/private/[REDACTED]'
      );
      expect(scrubUrlWithPatterns('/api/v3/receipt/token123')).toBe(
        '/api/v3/receipt/[REDACTED]'
      );
      expect(scrubUrlWithPatterns('/api/v3/incoming/data456')).toBe(
        '/api/v3/incoming/[REDACTED]'
      );
    });

    it('scrubs 62-char verifiable IDs', () => {
      const id62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';
      expect(scrubUrlWithPatterns(`/api/v3/unknown/${id62}`)).toBe(
        '/api/v3/unknown/[REDACTED]'
      );
    });

    it('scrubs email addresses in query params', () => {
      expect(scrubUrlWithPatterns('/api/users?email=user@example.com')).toBe(
        '/api/users?email=[EMAIL_REDACTED]'
      );
    });

    it('scrubs email addresses in path segments', () => {
      expect(scrubUrlWithPatterns('/api/users/user@example.com/profile')).toBe(
        '/api/users/[EMAIL_REDACTED]/profile'
      );
    });

    it('scrubs multiple emails in URL', () => {
      expect(
        scrubUrlWithPatterns('/api/share?from=alice@a.com&to=bob@b.com')
      ).toBe('/api/share?from=[EMAIL_REDACTED]&to=[EMAIL_REDACTED]');
    });

    it('leaves non-sensitive URLs unchanged', () => {
      expect(scrubUrlWithPatterns('/api/v3/colonel/status')).toBe(
        '/api/v3/colonel/status'
      );
      expect(scrubUrlWithPatterns('/api/health')).toBe('/api/health');
    });

    it('handles null/undefined gracefully', () => {
      expect(scrubUrlWithPatterns(null as unknown as string)).toBe(null);
      expect(scrubUrlWithPatterns(undefined as unknown as string)).toBe(undefined);
    });

    it('handles empty string', () => {
      expect(scrubUrlWithPatterns('')).toBe('');
    });

    it('preserves URL structure while scrubbing', () => {
      const url = 'https://api.example.com/api/v3/secret/abc123?email=test@test.com';
      const scrubbed = scrubUrlWithPatterns(url);
      expect(scrubbed).toBe(
        'https://api.example.com/api/v3/secret/[REDACTED]?email=[EMAIL_REDACTED]'
      );
    });
  });

  describe('pattern exports', () => {
    it('exports EMAIL_PATTERN', () => {
      expect(EMAIL_PATTERN).toBeInstanceOf(RegExp);
      expect('test@example.com'.match(EMAIL_PATTERN)).toBeTruthy();
    });

    it('exports SENSITIVE_PATH_PATTERN', () => {
      expect(SENSITIVE_PATH_PATTERN).toBeInstanceOf(RegExp);
    });

    it('exports VERIFIABLE_ID_PATTERN', () => {
      expect(VERIFIABLE_ID_PATTERN).toBeInstanceOf(RegExp);
    });
  });

  describe('sentinel invariant', () => {
    // Every redaction sentinel emitted by scrubSensitiveStrings or its peers
    // MUST match /^\[[A-Z_]+\]$/ — square-bracketed, uppercase, underscored,
    // whitespace-free. The pipeline applies multiple scrubbing passes in
    // sequence, and later passes use the path-scrub value class `[^/\s]+`.
    // A sentinel containing a literal space (e.g. the old `[EMAIL REDACTED]`)
    // causes the path regex to split mid-sentinel and produce cosmetically
    // corrupted output like `[REDACTED] REDACTED]`. The data is still
    // scrubbed but the sentinels stop composing cleanly. This test locks
    // the invariant in place: if a future scrubber introduces a sentinel
    // with whitespace or lowercase, it must update this list AND prove the
    // pipeline still composes.
    const SENTINEL_SHAPE = /^\[[A-Z_]+\]$/;
    const KNOWN_SENTINELS = ['[EMAIL_REDACTED]', '[REDACTED]'];

    it('all known sentinels match the shape /^\\[[A-Z_]+\\]$/', () => {
      for (const sentinel of KNOWN_SENTINELS) {
        expect(sentinel).toMatch(SENTINEL_SHAPE);
      }
    });

    it('no known sentinel contains whitespace', () => {
      for (const sentinel of KNOWN_SENTINELS) {
        expect(sentinel).not.toMatch(/\s/);
      }
    });

    it('composes cleanly when an email sits inside a sensitive URL path', () => {
      // Regression guard: the full pipeline should produce atomic output
      // (one [REDACTED] swallowing the whole URL tail) rather than splitting
      // a sentinel mid-token. Any regression to a whitespace-bearing sentinel
      // would show up here as `[REDACTED] REDACTED]` or similar.
      const msg = '/api/v1/secret/abcdef12345?email=user@example.com done';
      const result = scrubSensitiveStrings(msg);
      expect(result).toBe('/api/v1/secret/[REDACTED] done');
      expect(result).not.toContain(' REDACTED]');
      expect(result).not.toContain('[REDACTED][');
    });
  });
});

// ---------------------------------------------------------------------------
// A1 — sensitive query-parameter VALUE redaction by name
// ---------------------------------------------------------------------------
describe('scrubSensitiveQueryParams (A1)', () => {
  it('exports the backend-mirrored param name list', () => {
    expect([...SENSITIVE_QUERY_PARAMS]).toEqual(['key', 'secret', 'token', 'passphrase']);
  });

  it('redacts the value of each sensitive param, preserving the name', () => {
    expect(scrubSensitiveQueryParams('key=abc123')).toBe('key=[REDACTED]');
    expect(scrubSensitiveQueryParams('secret=abc123')).toBe('secret=[REDACTED]');
    expect(scrubSensitiveQueryParams('token=abc123')).toBe('token=[REDACTED]');
    expect(scrubSensitiveQueryParams('passphrase=abc123')).toBe('passphrase=[REDACTED]');
  });

  it('matches the param name case-insensitively', () => {
    expect(scrubSensitiveQueryParams('Token=abc123')).toBe('Token=[REDACTED]');
    expect(scrubSensitiveQueryParams('KEY=abc123')).toBe('KEY=[REDACTED]');
  });

  it('preserves benign params verbatim', () => {
    expect(scrubSensitiveQueryParams('product=identity&interval=month')).toBe(
      'product=identity&interval=month'
    );
  });

  it('redacts only the sensitive param in a mixed query', () => {
    expect(scrubSensitiveQueryParams('product=identity&token=abc123&interval=month')).toBe(
      'product=identity&token=[REDACTED]&interval=month'
    );
  });

  it('preserves empty trailing segments (round-trips a=1&)', () => {
    expect(scrubSensitiveQueryParams('a=1&')).toBe('a=1&');
  });

  it('leaves valueless flags untouched', () => {
    expect(scrubSensitiveQueryParams('token')).toBe('token');
  });

  it('handles null/undefined/empty gracefully', () => {
    expect(scrubSensitiveQueryParams(null as unknown as string)).toBe(null);
    expect(scrubSensitiveQueryParams('')).toBe('');
  });
});

describe('scrubUrlWithPatterns query-param redaction (A1)', () => {
  it('redacts a sensitive param value inside a full URL', () => {
    expect(scrubUrlWithPatterns('https://example.com/reveal?token=abc123')).toBe(
      'https://example.com/reveal?token=[REDACTED]'
    );
  });

  it('redacts a sensitive param and preserves the fragment', () => {
    expect(scrubUrlWithPatterns('/reveal?secret=abc123#section')).toBe(
      '/reveal?secret=[REDACTED]#section'
    );
  });

  it('leaves benign query params intact', () => {
    expect(scrubUrlWithPatterns('/pricing?product=identity&interval=month')).toBe(
      '/pricing?product=identity&interval=month'
    );
  });
});

// ---------------------------------------------------------------------------
// A4 — span http.query (bare query string) scrubbing
// ---------------------------------------------------------------------------
describe('scrubQueryStringValues (A4)', () => {
  it('redacts sensitive param values by name', () => {
    expect(scrubQueryStringValues('token=abc123&foo=bar')).toBe('token=[REDACTED]&foo=bar');
  });

  it('applies the email net to non-sensitive params', () => {
    expect(scrubQueryStringValues('email=user@example.com')).toBe('email=[EMAIL_REDACTED]');
  });

  it('applies the verifiable-id net to non-sensitive params', () => {
    expect(scrubQueryStringValues(`ref=${ID_VECTORS.id62}`)).toBe('ref=[REDACTED]');
  });

  it('handles null/undefined/empty gracefully', () => {
    expect(scrubQueryStringValues(null as unknown as string)).toBe(null);
    expect(scrubQueryStringValues('')).toBe('');
  });
});

// ---------------------------------------------------------------------------
// C1 — shared identifier test-vector set applied through the string scrubber
// ---------------------------------------------------------------------------
describe('C1 identifier vectors via scrubSensitiveStrings', () => {
  it('redacts the 62-char (current) identifier', () => {
    expect(scrubSensitiveStrings(`id ${ID_VECTORS.id62} end`)).toBe('id [REDACTED] end');
  });

  it('redacts the 31-char (legacy v0.23) identifier', () => {
    expect(scrubSensitiveStrings(`id ${ID_VECTORS.id31} end`)).toBe('id [REDACTED] end');
  });

  it('redacts a mixed-case identifier (frontend case-insensitive)', () => {
    expect(scrubSensitiveStrings(`id ${ID_VECTORS.id62mixed} end`)).toBe('id [REDACTED] end');
  });

  it('preserves a 32-char trace id (ops-useful)', () => {
    expect(scrubSensitiveStrings(`trace ${ID_VECTORS.traceId32} end`)).toBe(
      `trace ${ID_VECTORS.traceId32} end`
    );
  });

  it('preserves a 40-char commit hash (ops-useful)', () => {
    expect(scrubSensitiveStrings(`sha ${ID_VECTORS.commitHash40} end`)).toBe(
      `sha ${ID_VECTORS.commitHash40} end`
    );
  });

  it('preserves a short 6-char token', () => {
    expect(scrubSensitiveStrings(`x ${ID_VECTORS.short6} y`)).toBe(`x ${ID_VECTORS.short6} y`);
  });
});
