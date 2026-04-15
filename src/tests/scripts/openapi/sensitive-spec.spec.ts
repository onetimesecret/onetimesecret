// src/tests/scripts/openapi/sensitive-spec.spec.ts
//
// Unit tests for the shared sensitive-spec helper used by both the OpenAPI
// generator (x-sensitive metadata) and the Sentry scrub-patterns generator.
//
// Run:
//   pnpm test src/tests/scripts/openapi/sensitive-spec.spec.ts

import { describe, it, expect } from 'vitest';
import {
  API_MOUNT_PATHS,
  PARAM_VALUE_PATTERN,
  parseSensitiveSpec,
  pathToRegexPattern,
} from '../../../../scripts/openapi/sensitive-spec';

const ID20 = 'abcdefghijklmnopqrst';

describe('parseSensitiveSpec', () => {
  it('returns null for undefined, null, and empty string', () => {
    expect(parseSensitiveSpec(undefined)).toBeNull();
    expect(parseSensitiveSpec(null as unknown as string)).toBeNull();
    expect(parseSensitiveSpec('')).toBeNull();
    expect(parseSensitiveSpec('   ')).toBeNull();
  });

  it('returns true for literal "true"', () => {
    expect(parseSensitiveSpec('true')).toBe(true);
  });

  it('does not treat truthy-looking strings as true (strict equality only)', () => {
    // Regression guard: only the exact literal 'true' collapses to the
    // boolean sentinel. Anything else becomes a Set so the generator can
    // raise if the names do not match path params.
    for (const input of ['false', 'yes', 'no', '1', '0', 'True', 'TRUE']) {
      const result = parseSensitiveSpec(input);
      expect(result).not.toBe(true);
      expect(result).toBeInstanceOf(Set);
      expect((result as Set<string>).has(input)).toBe(true);
    }
  });

  it('parses a single-key list into a Set', () => {
    const result = parseSensitiveSpec('secret');
    expect(result).toBeInstanceOf(Set);
    expect(Array.from(result as Set<string>)).toEqual(['secret']);
  });

  it('parses a comma-separated list into a Set', () => {
    const result = parseSensitiveSpec('secret,token,receipt');
    expect(result).toBeInstanceOf(Set);
    expect(Array.from(result as Set<string>).sort()).toEqual([
      'receipt',
      'secret',
      'token',
    ]);
  });

  it('trims whitespace around keys', () => {
    const result = parseSensitiveSpec(' secret , token ');
    expect(Array.from(result as Set<string>).sort()).toEqual(['secret', 'token']);
  });

  it('drops empty entries from trailing or duplicate commas', () => {
    const result = parseSensitiveSpec('secret,,token,');
    expect(Array.from(result as Set<string>).sort()).toEqual(['secret', 'token']);
  });

  it('deduplicates repeated keys via Set semantics', () => {
    const result = parseSensitiveSpec('secret,secret,token');
    expect((result as Set<string>).size).toBe(2);
  });
});

describe('PARAM_VALUE_PATTERN', () => {
  it('is the permissive non-slash, non-whitespace path-segment class', () => {
    expect(PARAM_VALUE_PATTERN).toBe('[^/\\s]+');
  });

  it('compiles standalone and accepts any non-empty path segment', () => {
    const re = new RegExp(`^${PARAM_VALUE_PATTERN}$`);
    expect(re.test(ID20)).toBe(true);
    expect(re.test(ID20.toUpperCase())).toBe(true);
    expect(re.test('abc-123')).toBe(true);
    expect(re.test('short')).toBe(true);
    expect(re.test('x')).toBe(true);
  });

  it('rejects path separators, empty strings, and whitespace', () => {
    // For URL inputs, callers normalize through `URL` before invoking the
    // generated patterns, so `?` and `#` never reach this class — the
    // greedy `[^/\s]+` would otherwise capture them and carry the query
    // string into the replacement. Whitespace is excluded so that, in
    // free-form exception text, trailing log context (e.g. " failed with
    // 500") is preserved instead of being eaten into the capture.
    const re = new RegExp(`^${PARAM_VALUE_PATTERN}$`);
    expect(re.test('')).toBe(false);
    expect(re.test('a/b')).toBe(false);
    expect(re.test('a b')).toBe(false);
    expect(re.test('a\tb')).toBe(false);
    expect(re.test('a\nb')).toBe(false);
  });
});

describe('API_MOUNT_PATHS', () => {
  it('is exported as a shared constant for both generators', () => {
    expect(API_MOUNT_PATHS.v1).toBe('/api/v1');
    expect(API_MOUNT_PATHS.v2).toBe('/api/v2');
    expect(API_MOUNT_PATHS.v3).toBe('/api/v3');
  });
});

describe('pathToRegexPattern', () => {
  it('emits an unanchored pattern', () => {
    const { regex } = pathToRegexPattern('/api/v1/secret/:key', true);
    expect(regex.startsWith('^')).toBe(false);
    expect(regex.endsWith('$')).toBe(false);
  });

  it('captures every param when spec=true', () => {
    const { regex, captureCount } = pathToRegexPattern(
      '/foo/:a/:b/:c',
      true
    );
    expect(captureCount).toBe(3);
    const compiled = new RegExp(regex);
    const match = `/foo/${ID20}/${ID20}/${ID20}`.match(compiled);
    expect(match).not.toBeNull();
    expect(match?.slice(1)).toEqual([ID20, ID20, ID20]);
  });

  it('captures only listed params in a multi-param path', () => {
    const { regex, captureCount } = pathToRegexPattern(
      '/foo/:secret/:page',
      new Set(['secret'])
    );
    // :secret becomes a capture group; :page becomes non-capturing.
    expect(regex).toBe('\\/foo\\/([^/\\s]+)\\/(?:[^/\\s]+)');
    expect(captureCount).toBe(1);

    const compiled = new RegExp(regex);
    const match = `/foo/${ID20}/${ID20}`.match(compiled);
    expect(match).not.toBeNull();
    expect(match?.[1]).toBe(ID20); // only :secret captured
    expect(match?.length).toBe(2); // full match + 1 capture
  });

  it('captures multiple listed params when spec lists more than one', () => {
    const { regex, captureCount } = pathToRegexPattern(
      '/foo/:a/:b/:c',
      new Set(['a', 'c'])
    );
    expect(captureCount).toBe(2);
    const compiled = new RegExp(regex);
    const match = `/foo/${ID20}/${ID20}/${ID20}`.match(compiled);
    expect(match?.slice(1).length).toBe(2);
  });

  it('returns captureCount=0 when no listed param is present in the path', () => {
    const { regex, captureCount } = pathToRegexPattern(
      '/foo/:page',
      new Set(['nonexistent'])
    );
    expect(captureCount).toBe(0);
    // The :page param still appears as a non-capturing group so the regex is
    // syntactically valid. The generator treats a zero count from a sensitive
    // route as an error (misconfigured annotation).
    expect(regex).toContain('(?:[^/\\s]+)');
    expect(regex).not.toContain('([^/\\s]+)');
  });

  it('emits capture groups using the permissive value class', () => {
    const { regex } = pathToRegexPattern('/api/v1/secret/:key', true);
    expect(regex).toContain('([^/\\s]+)');
    // No grammar carriers — scrubbing is structural (per param position),
    // not per-value.
    expect(regex).not.toContain('[0-9a-z]');
  });

  it('escapes regex metacharacters in literal segments', () => {
    const { regex } = pathToRegexPattern('/a.b+c/:key', true);
    expect(regex).toContain('\\.');
    expect(regex).toContain('\\+');
    const compiled = new RegExp(regex);
    expect(compiled.test(`/a.b+c/${ID20}`)).toBe(true);
    expect(compiled.test(`/axbxc/${ID20}`)).toBe(false);
  });

  it('escapes forward slashes so the source is embeddable in /.../ literals', () => {
    const { regex } = pathToRegexPattern('/foo/bar', true);
    // Every separator becomes \/ so the emitted string can be wrapped as
    // /\/foo\/bar/g without breaking the literal.
    expect(regex).toBe('\\/foo\\/bar');
  });

  it('emits an unanchored pattern that matches a route substring', () => {
    // Unanchored: /api/v1/secret/:key matches /api/v1/secret/abc on its
    // own AND inside /api/v1/secret/abc/burn — the pattern matches a
    // substring and the trailing /burn is preserved by the caller.
    const { regex } = pathToRegexPattern('/api/v1/secret/:key', true);
    const compiled = new RegExp(regex);
    expect(compiled.test(`/api/v1/secret/${ID20}`)).toBe(true);
    expect(compiled.test(`/api/v1/secret/${ID20}/burn`)).toBe(true);
  });

  it('captures two params for spec=true on /foo/:a/:b', () => {
    // Explicit two-param coverage: matches the matrix row verbatim. The
    // 3-param case above is a superset but this isolates the common shape
    // that sensitive routes actually use (e.g. /v3/secret/:identifier/status
    // has one param; multi-param sensitive routes are rarer and warrant
    // their own regression row).
    const { regex, captureCount } = pathToRegexPattern('/foo/:a/:b', true);
    expect(captureCount).toBe(2);
    const compiled = new RegExp(regex);
    const match = `/foo/${ID20}/xyz`.match(compiled);
    expect(match?.slice(1)).toEqual([ID20, 'xyz']);
  });

  it('captures only :a on /foo/:a/:b when spec lists :a alone', () => {
    const { regex, captureCount } = pathToRegexPattern(
      '/foo/:a/:b',
      new Set(['a'])
    );
    expect(captureCount).toBe(1);
    // :a -> capturing, :b -> non-capturing
    expect(regex).toBe('\\/foo\\/([^/\\s]+)\\/(?:[^/\\s]+)');
  });

  it('handles repeated param names in a single path (/a/:x/b/:x)', () => {
    // If the same :x appears twice and spec names :x, both occurrences
    // become capture groups. This is an unusual but syntactically valid
    // route shape; the function should not special-case uniqueness.
    const { regex, captureCount } = pathToRegexPattern(
      '/a/:x/b/:x',
      new Set(['x'])
    );
    expect(captureCount).toBe(2);
    const compiled = new RegExp(regex);
    const match = `/a/${ID20}/b/xyz`.match(compiled);
    expect(match?.slice(1)).toEqual([ID20, 'xyz']);
  });

  it('returns a source string without regex flags baked in', () => {
    // pathToRegexPattern returns a raw source string; the caller decides
    // what flags to wrap it in. Verify the source contains no inline flag
    // modifier like (?i) and no trailing flag suffix.
    const { regex } = pathToRegexPattern('/foo/:a', true);
    expect(regex).not.toContain('(?i');
    expect(regex).not.toMatch(/\/[gimsuy]+$/);
  });

  it('matches a route substring inside a fully-qualified URL', () => {
    // Unanchored: the host prefix in https://example.com/api/v1/secret/<id>
    // is skipped and the pattern finds `/api/v1/secret/<id>` as a substring.
    // Runtime callers in src/plugins/core/diagnostics/scrubbers.ts still
    // normalize through `URL` before invoking the patterns so the query
    // string is not pulled into the capture group — the value class
    // ([^/\s]+) deliberately does NOT exclude `?` or `#`.
    const { regex } = pathToRegexPattern('/api/v1/secret/:key', true);
    const compiled = new RegExp(regex);
    expect(compiled.test(`https://example.com/api/v1/secret/${ID20}`)).toBe(true);
  });
});
