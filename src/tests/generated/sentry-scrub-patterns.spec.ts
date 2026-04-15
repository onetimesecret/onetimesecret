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

    it('every pattern is anchored with ^...$', () => {
      // Structural invariant. Anchoring is load-bearing for precision.
      // Runtime callers in scrubbers.ts strip host/query/hash before invoking
      // these patterns — see the anchoring regression tests below.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.source.startsWith('^')).toBe(true);
        expect(pattern.source.endsWith('$')).toBe(true);
      });
    });

    it('every pattern embeds the permissive param value class', () => {
      // Scrubbing is structural (per param position), not per-value-grammar.
      // Capture groups match any non-slash path segment. Callers normalize
      // input to a bare pathname (host/query/fragment stripped) before
      // invoking the anchored patterns — see extractAndScrubPath.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.source).toContain('([^/]+)');
      });
    });

    it('no pattern embeds a grammar carrier class', () => {
      // Defense against regressions: no test, generator, or emitter should
      // reintroduce a value-grammar class like [0-9a-z]{20,}.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.source).not.toContain('[0-9a-z]');
      });
    });

    it('no pattern carries the case-insensitive flag', () => {
      // The old emitter used /.../gi; the new emitter drops the `i` flag
      // because the permissive [^/]+ class already matches any case. A
      // regression to `i` would be harmless at runtime but would indicate
      // someone hand-edited the generated file or regenerated with a stale
      // template.
      SENSITIVE_PATH_PATTERNS.forEach((pattern) => {
        expect(pattern.ignoreCase).toBe(false);
        expect(pattern.flags).toBe('g');
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
        expect(pattern.source.startsWith('^\\/api\\/')).toBe(true);
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
        // abc-123 -> [REDACTED]-123. The permissive [^/]+ class captures
        // the entire path segment, so abc-123 becomes [REDACTED] atomically.
        expect(scrubSensitivePath('/api/v3/secret/abc-123')).toBe(
          '/api/v3/secret/[REDACTED]'
        );
      });

      it('leaves a trailing-slash path with empty :identifier unchanged', () => {
        // Anchored pattern requires the capture group to match at least one
        // character (`[^/]+`). `/api/v3/secret/` has an empty final segment,
        // so no pattern matches and the input is returned verbatim. This
        // locks in that an empty :identifier is not redacted to [REDACTED].
        expect(scrubSensitivePath('/api/v3/secret/')).toBe('/api/v3/secret/');
      });

      it('leaves a path with an extra trailing segment unchanged', () => {
        // The anchored pattern for /api/v3/secret/:identifier does not
        // match /api/v3/secret/abc/extra because the trailing /extra would
        // need its own route in the sensitive set. scrubSensitivePath
        // applies only the generated patterns, so the input is returned
        // verbatim. (scrubUrlWithPatterns would still catch this via the
        // legacy fallback pattern — covered separately in scrubUrl tests.)
        expect(scrubSensitivePath('/api/v3/secret/abc/extra')).toBe(
          '/api/v3/secret/abc/extra'
        );
      });

      it('does not double-scrub already scrubbed paths', () => {
        // [REDACTED] itself matches [^/]+, so a second pass replaces the
        // literal sentinel with itself. The final output is stable under
        // re-application.
        const alreadyScrubbed = '/api/v3/secret/[REDACTED]';
        expect(scrubSensitivePath(alreadyScrubbed)).toBe(alreadyScrubbed);
      });
    });

    describe('anchoring regression — callers apply anchored patterns correctly', () => {
      // The generated patterns are anchored with ^/$ so they only match a
      // bare pathname. The runtime callers in scrubbers.ts are responsible
      // for stripping host+query before invoking the generated patterns:
      //
      //   - scrubUrlWithPatterns() parses full URLs and scrubs the pathname
      //     only, reassembling protocol/host/search/hash around the result.
      //   - scrubSensitiveStrings() relies on the legacy SENSITIVE_PATH_PATTERN
      //     fallback to catch paths embedded in free-form exception text.
      //
      // These specs lock in that the Sentry breadcrumb path (full URL) and
      // the axios interceptor path (bare path+query) both produce scrubbed
      // output at the runtime boundary.

      it('should scrub full URLs with host prefix (fix anchoring regression)', () => {
        const fullUrl = `https://example.com/api/v1/secret/${ID20}`;
        expect(scrubUrlWithPatterns(fullUrl)).toBe(
          'https://example.com/api/v1/secret/[REDACTED]'
        );
      });

      it('should scrub paths with query string suffix (fix anchoring regression)', () => {
        const pathWithQuery = `/api/v1/secret/${ID20}?foo=bar`;
        expect(scrubUrlWithPatterns(pathWithQuery)).toBe(
          '/api/v1/secret/[REDACTED]?foo=bar'
        );
      });

      it('should scrub sensitive paths embedded in exception message text (fix anchoring regression)', () => {
        // scrubSensitiveStrings uses the legacy SENSITIVE_PATH_PATTERN
        // fallback for free-form text — the anchored generated patterns do
        // not participate in exception-text scrubbing, which is acceptable.
        const msg = `Request to /api/v1/secret/${ID20} failed with 500`;
        expect(scrubSensitiveStrings(msg)).toBe(
          'Request to /api/v1/secret/[REDACTED] failed with 500'
        );
      });
    });
  });

  describe('pathToRegexPattern', () => {
    it('exposes PARAM_VALUE_PATTERN as the permissive value class', () => {
      expect(PARAM_VALUE_PATTERN).toBe('[^/]+');
    });

    it('produces an anchored, capturing pattern for spec=true', () => {
      const { regex, captureCount } = pathToRegexPattern(
        '/api/v1/secret/:key',
        true
      );
      expect(regex).toBe('^\\/api\\/v1\\/secret\\/([^/]+)$');
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
      expect(regex).toBe('^\\/api\\/v1\\/thing\\/(?:[^/]+)\\/([^/]+)$');
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
