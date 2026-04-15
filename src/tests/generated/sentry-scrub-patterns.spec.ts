// src/tests/generated/sentry-scrub-patterns.spec.ts
//
// Tests for the auto-generated Sentry scrub patterns.
// These tests verify that scrubSensitivePath() correctly redacts sensitive
// identifiers from API paths derived from route metadata.
//
// Run:
//   pnpm test src/tests/generated/sentry-scrub-patterns.spec.ts

import { describe, it, expect } from 'vitest';
import {
  scrubSensitivePath,
  SENSITIVE_PATH_PATTERNS,
} from '@/generated/sentry-scrub-patterns';
import {
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from '@/plugins/core/diagnostics/scrubbers';
import {
  PARAM_VALUE_PATTERN,
  pathToRegexPattern,
} from '../../../scripts/openapi/sensitive-spec';

// A representative 20-char lowercase identifier.
const ID20 = 'abcdefghijklmnopqrst';
// A 62-char identifier matching the full v0.24 VerifiableIdentifier length.
const ID62 = 'abcdefghijklmnopqrstuvwxyz0123456789abcdefghijklmnopqrstuvwxyz';

describe('generated sentry-scrub-patterns', () => {
  describe('SENSITIVE_PATH_PATTERNS', () => {
    it('exports an array of RegExp patterns', () => {
      expect(Array.isArray(SENSITIVE_PATH_PATTERNS)).toBe(true);
      expect(SENSITIVE_PATH_PATTERNS.length).toBeGreaterThan(0);
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern).toBeInstanceOf(RegExp);
      });
    });

    it('contains patterns for v1, v2, and v3 APIs', () => {
      const patternStrings = SENSITIVE_PATH_PATTERNS.map((p) => p.source);
      expect(patternStrings.some((s) => s.includes('api\\/v1'))).toBe(true);
      expect(patternStrings.some((s) => s.includes('api\\/v2'))).toBe(true);
      expect(patternStrings.some((s) => s.includes('api\\/v3'))).toBe(true);
    });

    it('emits the global flag so replace() visits every match', () => {
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.global).toBe(true);
      });
    });

    it('no pattern is anchored with ^ or $', () => {
      // Structural invariant. Patterns are unanchored so they can match a
      // route substring inside a fully-qualified URL or inside free-form
      // exception text. Query/fragment protection for URL inputs is handled
      // at the runtime boundary (`extractAndScrubPath`), not by anchoring.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.source.startsWith('^')).toBe(false);
        expect(pattern.source.endsWith('$')).toBe(false);
      });
    });

    it('every pattern embeds the permissive param value class', () => {
      // Scrubbing is structural (per param position), not per-value-grammar.
      // Capture groups match any non-slash path segment. For URL inputs,
      // callers normalize through `URL` before invoking the patterns so the
      // query string is not pulled into the capture — see extractAndScrubPath.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.source).toContain('([^/\\s]+)');
      });
    });

    it('no pattern embeds a grammar carrier class', () => {
      // Defense against regressions: no test, generator, or emitter should
      // reintroduce a value-grammar class like [0-9a-z]{20,}.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.source).not.toContain('[0-9a-z]');
      });
    });

    it('every pattern carries the case-insensitive flag', () => {
      // The capture class [^/\s]+ already matches any case, but the static
      // path literals (e.g. \/api\/v1\/secret\/) are case-sensitive without
      // the `i` flag. Unusual casing like `/API/v1/secret/<id>` can show up
      // in free-form exception text and third-party breadcrumb URLs even
      // though Otto routes are canonically lowercase. Keep `i` so those
      // paths still match and get scrubbed.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.ignoreCase).toBe(true);
        expect(pattern.flags).toBe('gi');
      });
    });

    it('emits one pattern per unique sensitive route (currently 27)', () => {
      // Sanity check: if Otto route annotations change, this number moves.
      // Update it deliberately. A sudden drop usually means a sensitive=
      // annotation was removed; a jump means one was added.
      expect(SENSITIVE_PATH_PATTERNS.length).toBe(27);
    });

    it('every pattern begins with an escaped /api/ mount path', () => {
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        // Generator emits \/api\/ for the mount root. A pattern that starts
        // any other way would indicate a bug in getFullPath or mount-path map.
        expect(pattern.source.startsWith('\\/api\\/')).toBe(true);
      });
    });
  });

  describe('scrubSensitivePath', () => {
    describe('v1 API paths', () => {
      it('scrubs /api/v1/secret/:key', () => {
        expect(scrubSensitivePath(`/api/v1/secret/${ID20}`)).toBe(
          '/api/v1/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v1/metadata/:key', () => {
        expect(scrubSensitivePath(`/api/v1/metadata/${ID20}`)).toBe(
          '/api/v1/metadata/[REDACTED]'
        );
      });

      it('scrubs /api/v1/metadata/:key/burn', () => {
        expect(scrubSensitivePath(`/api/v1/metadata/${ID20}/burn`)).toBe(
          '/api/v1/metadata/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v1/private/:key', () => {
        expect(scrubSensitivePath(`/api/v1/private/${ID20}`)).toBe(
          '/api/v1/private/[REDACTED]'
        );
      });

      it('scrubs /api/v1/private/:key/burn', () => {
        expect(scrubSensitivePath(`/api/v1/private/${ID20}/burn`)).toBe(
          '/api/v1/private/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v1/receipt/:key', () => {
        expect(scrubSensitivePath(`/api/v1/receipt/${ID20}`)).toBe(
          '/api/v1/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v1/receipt/:key/burn', () => {
        expect(scrubSensitivePath(`/api/v1/receipt/${ID20}/burn`)).toBe(
          '/api/v1/receipt/[REDACTED]/burn'
        );
      });
    });

    describe('v2 API paths', () => {
      it('scrubs /api/v2/secret/:identifier', () => {
        expect(scrubSensitivePath(`/api/v2/secret/${ID20}`)).toBe(
          '/api/v2/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v2/secret/:identifier/reveal', () => {
        expect(scrubSensitivePath(`/api/v2/secret/${ID20}/reveal`)).toBe(
          '/api/v2/secret/[REDACTED]/reveal'
        );
      });

      it('scrubs /api/v2/secret/:identifier/status', () => {
        expect(scrubSensitivePath(`/api/v2/secret/${ID20}/status`)).toBe(
          '/api/v2/secret/[REDACTED]/status'
        );
      });

      it('scrubs /api/v2/private/:identifier', () => {
        expect(scrubSensitivePath(`/api/v2/private/${ID20}`)).toBe(
          '/api/v2/private/[REDACTED]'
        );
      });

      it('scrubs /api/v2/private/:identifier/burn', () => {
        expect(scrubSensitivePath(`/api/v2/private/${ID20}/burn`)).toBe(
          '/api/v2/private/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v2/receipt/:identifier', () => {
        expect(scrubSensitivePath(`/api/v2/receipt/${ID20}`)).toBe(
          '/api/v2/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v2/receipt/:identifier/burn', () => {
        expect(scrubSensitivePath(`/api/v2/receipt/${ID20}/burn`)).toBe(
          '/api/v2/receipt/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v2/guest/secret/:identifier', () => {
        expect(scrubSensitivePath(`/api/v2/guest/secret/${ID20}`)).toBe(
          '/api/v2/guest/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v2/guest/secret/:identifier/reveal', () => {
        expect(
          scrubSensitivePath(`/api/v2/guest/secret/${ID20}/reveal`)
        ).toBe('/api/v2/guest/secret/[REDACTED]/reveal');
      });

      it('scrubs /api/v2/guest/receipt/:identifier', () => {
        expect(scrubSensitivePath(`/api/v2/guest/receipt/${ID20}`)).toBe(
          '/api/v2/guest/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v2/guest/receipt/:identifier/burn', () => {
        expect(
          scrubSensitivePath(`/api/v2/guest/receipt/${ID20}/burn`)
        ).toBe('/api/v2/guest/receipt/[REDACTED]/burn');
      });
    });

    describe('v3 API paths', () => {
      it('scrubs /api/v3/secret/:identifier', () => {
        expect(scrubSensitivePath(`/api/v3/secret/${ID20}`)).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v3/secret/:identifier/reveal', () => {
        expect(scrubSensitivePath(`/api/v3/secret/${ID20}/reveal`)).toBe(
          '/api/v3/secret/[REDACTED]/reveal'
        );
      });

      it('scrubs /api/v3/secret/:identifier/status', () => {
        expect(scrubSensitivePath(`/api/v3/secret/${ID20}/status`)).toBe(
          '/api/v3/secret/[REDACTED]/status'
        );
      });

      it('scrubs /api/v3/receipt/:identifier', () => {
        expect(scrubSensitivePath(`/api/v3/receipt/${ID20}`)).toBe(
          '/api/v3/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v3/receipt/:identifier/burn', () => {
        expect(scrubSensitivePath(`/api/v3/receipt/${ID20}/burn`)).toBe(
          '/api/v3/receipt/[REDACTED]/burn'
        );
      });

      it('scrubs /api/v3/guest/secret/:identifier', () => {
        expect(scrubSensitivePath(`/api/v3/guest/secret/${ID20}`)).toBe(
          '/api/v3/guest/secret/[REDACTED]'
        );
      });

      it('scrubs /api/v3/guest/secret/:identifier/reveal', () => {
        expect(
          scrubSensitivePath(`/api/v3/guest/secret/${ID20}/reveal`)
        ).toBe('/api/v3/guest/secret/[REDACTED]/reveal');
      });

      it('scrubs /api/v3/guest/receipt/:identifier', () => {
        expect(scrubSensitivePath(`/api/v3/guest/receipt/${ID20}`)).toBe(
          '/api/v3/guest/receipt/[REDACTED]'
        );
      });

      it('scrubs /api/v3/guest/receipt/:identifier/burn', () => {
        expect(
          scrubSensitivePath(`/api/v3/guest/receipt/${ID20}/burn`)
        ).toBe('/api/v3/guest/receipt/[REDACTED]/burn');
      });
    });

    describe('edge cases', () => {
      it('handles empty string', () => {
        expect(scrubSensitivePath('')).toBe('');
      });

      it('leaves non-sensitive paths unchanged', () => {
        expect(scrubSensitivePath('/api/v3/colonel/status')).toBe(
          '/api/v3/colonel/status'
        );
        expect(scrubSensitivePath('/api/health')).toBe('/api/health');
        expect(scrubSensitivePath('/pricing')).toBe('/pricing');
      });

      it('scrubs full 62-char VerifiableIdentifier', () => {
        expect(scrubSensitivePath(`/api/v3/secret/${ID62}`)).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs uppercase identifiers (case-insensitive structural match)', () => {
        // Scrubbing is structural: anything in the :identifier slot gets
        // redacted regardless of case or grammar.
        const upper = 'ABCDEFGHIJKLMNOPQRSTUV';
        expect(scrubSensitivePath(`/api/v3/secret/${upper}`)).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs mixed-case identifiers', () => {
        const mixed = 'Abcdefghijklmnopqrst';
        expect(scrubSensitivePath(`/api/v3/secret/${mixed}`)).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs short identifiers regardless of length', () => {
        // No MIN_IDENTIFIER_LENGTH gate — the structural match redacts
        // whatever value occupies the :identifier segment.
        const short = 'abc';
        expect(scrubSensitivePath(`/api/v3/secret/${short}`)).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('scrubs the full segment for hyphenated values (no half-scrub)', () => {
        // Regression: the old [a-zA-Z0-9]+ grammar produced half-scrubs like
        // abc-123 -> [REDACTED]-123. The permissive [^/\s]+ class captures
        // the entire path segment, so abc-123 becomes [REDACTED] atomically.
        expect(scrubSensitivePath('/api/v3/secret/abc-123')).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('leaves a trailing-slash path with empty :identifier unchanged', () => {
        // The pattern requires the capture group to match at least one
        // character (`[^/\s]+`). `/api/v3/secret/` has an empty final segment,
        // so no pattern matches and the input is returned verbatim. This
        // locks in that an empty :identifier is not redacted to [REDACTED].
        expect(scrubSensitivePath('/api/v3/secret/')).toBe('/api/v3/secret/');
      });

      it('scrubs a path with an extra trailing segment', () => {
        // Unanchored patterns match a route substring. For
        // /api/v3/secret/abc/extra, the generated pattern for
        // /api/v3/secret/:identifier matches the /api/v3/secret/abc
        // substring and redacts abc. The trailing /extra is preserved.
        expect(scrubSensitivePath('/api/v3/secret/abc/extra')).toBe(
          '/api/v3/secret/[REDACTED]/extra'
        );
      });

      it('does not double-scrub already scrubbed paths', () => {
        // [REDACTED] itself matches [^/\s]+, so a second pass replaces the
        // literal sentinel with itself. The final output is stable under
        // re-application.
        const alreadyScrubbed = '/api/v3/secret/[REDACTED]';
        expect(scrubSensitivePath(alreadyScrubbed)).toBe(alreadyScrubbed);
      });
    });

    describe('URL boundary scrubbing — callers preserve query/fragment', () => {
      // Patterns are unanchored so they can match a route substring inside a
      // full URL or inside free-form text. For URL inputs the runtime caller
      // still normalizes through `URL` so that the capture group never pulls
      // in the query string or fragment (`[^/\s]+` does not stop at `?` or
      // `#`).
      //
      //   - scrubUrlWithPatterns() parses full URLs and scrubs only the
      //     pathname, reassembling protocol/host/search/hash around it.
      //   - scrubSensitiveStrings() applies the generated patterns directly
      //     to free-form text, giving it coverage for routes the legacy
      //     SENSITIVE_PATH_PATTERN does not list (e.g. /metadata/). The
      //     whitespace boundary in `[^/\s]+` stops the capture at the end
      //     of the embedded URL so trailing log context is preserved. Any
      //     query string or fragment attached to the embedded URL goes
      //     down with the identifier — a fail-safe against sensitive data
      //     leaking through query params.

      it('scrubs full URLs with host prefix while preserving protocol/host', () => {
        const fullUrl = `https://example.com/api/v1/secret/${ID20}`;
        expect(scrubUrlWithPatterns(fullUrl)).toBe(
          'https://example.com/api/v1/secret/[REDACTED]'
        );
      });

      it('scrubs paths with query string suffix while preserving the query', () => {
        const pathWithQuery = `/api/v1/secret/${ID20}?foo=bar`;
        expect(scrubUrlWithPatterns(pathWithQuery)).toBe(
          '/api/v1/secret/[REDACTED]?foo=bar'
        );
      });

      it('scrubs sensitive paths embedded in exception text, preserving trailing context', () => {
        // The `[^/\s]+` class stops the capture at the first whitespace
        // character, so trailing log context after the URL is preserved
        // instead of being eaten into the REDACTED replacement.
        const msg = `Request to /api/v1/secret/${ID20} failed with 500`;
        expect(scrubSensitiveStrings(msg)).toBe(
          'Request to /api/v1/secret/[REDACTED] failed with 500'
        );
      });

      it('scrubs routes that the legacy fallback does not cover (e.g. metadata)', () => {
        // /api/v1/metadata/:key is not in the legacy SENSITIVE_PATH_PATTERN
        // fallback. Before the unanchoring fix, scrubSensitiveStrings had
        // no way to catch it in free-form text; the generated pattern now
        // does the work.
        const msg = `/api/v1/metadata/${ID20}`;
        expect(scrubSensitiveStrings(msg)).toBe('/api/v1/metadata/[REDACTED]');
      });

      // Table of inputs that previously would have been corrupted by the
      // `[^/]+` class (greedy consumption of trailing text, query-string
      // leakage in free text, multi-line logs pulling in the next line).
      // Each case exercises a distinct boundary behaviour of the
      // whitespace-excluding class used by scrubSensitiveStrings.
      const freeTextCases: Array<{
        name: string;
        input: string;
        expected: string;
      }> = [
        {
          name: 'URL with query string embedded in sentence',
          input: `Check /api/v1/secret/${ID20}?foo=bar in the logs`,
          expected: 'Check /api/v1/secret/[REDACTED] in the logs',
        },
        {
          name: 'URL with fragment embedded in sentence',
          input: `See /api/v1/secret/${ID20}#section later`,
          expected: 'See /api/v1/secret/[REDACTED] later',
        },
        {
          name: 'URL with query and fragment together',
          input: `At /api/v1/secret/${ID20}?a=1&b=2#top please investigate`,
          expected: 'At /api/v1/secret/[REDACTED] please investigate',
        },
        {
          // scrubSensitiveStrings runs EMAIL_PATTERN before scrubSensitivePath,
          // so the email is rewritten first. Because the email sentinel
          // `[EMAIL_REDACTED]` is whitespace-free, the path regex's
          // `[^/\s]+` class sees the full `abc?email=[EMAIL_REDACTED]` as
          // a single capture and replaces it atomically. Regression guard:
          // if someone reintroduces a space into any sentinel token, this
          // test will split and fail.
          name: 'URL with sensitive email query param (fail-safe, atomic)',
          input: `Hit /api/v1/secret/${ID20}?email=user@example.com now`,
          expected: 'Hit /api/v1/secret/[REDACTED] now',
        },
        {
          name: 'multi-line stack frame after URL',
          input: `Error: bad request /api/v1/secret/${ID20}\n    at handler.js:42`,
          expected:
            'Error: bad request /api/v1/secret/[REDACTED]\n    at handler.js:42',
        },
        {
          name: 'URL at end of string (no trailing whitespace)',
          input: `/api/v1/secret/${ID20}`,
          expected: '/api/v1/secret/[REDACTED]',
        },
        {
          name: 'URL followed by tab-delimited log column',
          input: `req\t/api/v1/secret/${ID20}\t500`,
          expected: 'req\t/api/v1/secret/[REDACTED]\t500',
        },
        {
          name: 'two URLs on the same line',
          input: `First /api/v1/secret/${ID20} then /api/v1/metadata/${ID20}`,
          expected:
            'First /api/v1/secret/[REDACTED] then /api/v1/metadata/[REDACTED]',
        },
        {
          name: 'URL inside parens (paren eaten — cosmetic)',
          input: `(see /api/v1/secret/${ID20}) for details`,
          expected: '(see /api/v1/secret/[REDACTED] for details',
        },
        {
          name: 'URL followed by sentence-terminating period',
          input: `Failed on /api/v1/secret/${ID20}. Retry pending.`,
          expected: 'Failed on /api/v1/secret/[REDACTED] Retry pending.',
        },
        {
          name: 'fully-qualified URL with query in free text',
          input: `GET https://example.com/api/v1/secret/${ID20}?token=abc HTTP/1.1`,
          expected:
            'GET https://example.com/api/v1/secret/[REDACTED] HTTP/1.1',
        },
        {
          name: 'metadata route embedded in log line',
          input: `[2026-04-15] /api/v1/metadata/${ID20} -> 200 OK`,
          expected: '[2026-04-15] /api/v1/metadata/[REDACTED] -> 200 OK',
        },
      ];

      freeTextCases.forEach(({ name, input, expected }) => {
        it(`free-text case: ${name}`, () => {
          expect(scrubSensitiveStrings(input)).toBe(expected);
        });
      });
    });
  });

  describe('pathToRegexPattern', () => {
    it('exposes PARAM_VALUE_PATTERN as the permissive value class', () => {
      expect(PARAM_VALUE_PATTERN).toBe('[^/\\s]+');
    });

    it('produces an unanchored, capturing pattern for spec=true', () => {
      const { regex, captureCount } = pathToRegexPattern(
        '/api/v1/secret/:key',
        true
      );
      expect(regex).toBe('\\/api\\/v1\\/secret\\/([^/\\s]+)');
      expect(captureCount).toBe(1);

      const compiled = new RegExp(regex);
      expect(compiled.test(`/api/v1/secret/${ID20}`)).toBe(true);
      expect(compiled.test('/api/v1/secret/short')).toBe(true);
    });

    it('captures only listed params when spec is a Set', () => {
      const { regex, captureCount } = pathToRegexPattern(
        '/api/v1/thing/:public/:secret',
        new Set(['secret'])
      );
      expect(regex).toBe('\\/api\\/v1\\/thing\\/(?:[^/\\s]+)\\/([^/\\s]+)');
      expect(captureCount).toBe(1);
    });

    it('reports captureCount=0 when no listed param matches the path', () => {
      // Route declares sensitive=missing but path has no :missing param.
      // The generator treats this as an error and throws before calling here;
      // this test exercises the raw counting behaviour directly.
      const { captureCount } = pathToRegexPattern(
        '/api/v1/thing/:other',
        new Set(['missing'])
      );
      expect(captureCount).toBe(0);
    });

    it('escapes regex metacharacters in literal segments', () => {
      const { regex } = pathToRegexPattern('/api/v1/a.b+c/:key', true);
      // Dot and plus must be escaped so they match literally, not as regex metachars.
      expect(regex).toContain('\\.');
      expect(regex).toContain('\\+');

      const compiled = new RegExp(regex);
      expect(compiled.test(`/api/v1/a.b+c/${ID20}`)).toBe(true);
      expect(compiled.test(`/api/v1/axbxc/${ID20}`)).toBe(false);
    });

    it('produces patterns that match any-case identifiers (structural)', () => {
      const { regex } = pathToRegexPattern('/api/v1/secret/:key', true);
      const compiled = new RegExp(regex);
      expect(compiled.test('/api/v1/secret/ABCDEFGHIJKLMNOPQRST')).toBe(true);
      expect(compiled.test('/api/v1/secret/MixedCase123')).toBe(true);
    });
  });
});
