// scripts/openapi/sensitive-spec.ts
//
// Shared parsing/emission helpers for the `sensitive=` route annotation.
// Used by both the OpenAPI generator (for x-sensitive metadata) and the
// Sentry scrub-patterns generator (for regex pattern emission).

/**
 * Permissive value class used by Otto-generated scrub patterns.
 *
 * Scrubbing is per-param-name (structural), NOT per-value-grammar. A sensitive
 * path segment is scrubbed because of *where* it sits in the route, not
 * because its value looks like an identifier. Otto-generated patterns match
 * structurally by param position; they are a defense layer complementing
 * vue-router meta (also position-based) and the legacy regex fallback
 * (grammar-based, for free-form exception text). No value grammar lives here.
 *
 * The class captures any non-slash, non-whitespace path segment. Generated
 * patterns are unanchored so they match path substrings inside full URLs and
 * inside free-form text.
 *
 * Two boundary behaviours follow from excluding whitespace:
 *
 *   1. URL inputs: valid URL pathnames never contain whitespace (spaces are
 *      percent-encoded as `%20`), so this class is equivalent to `[^/]+` on
 *      parsed pathnames. Callers still normalize URL inputs through `URL` in
 *      `extractAndScrubPath` so the query string and fragment are preserved
 *      verbatim around the scrubbed pathname — the class does not stop at
 *      `?` or `#`, and applying the pattern directly to a raw URL would
 *      otherwise pull the query string into the capture group.
 *
 *   2. Free-form text: the class stops at the first whitespace character
 *      after the identifier. Trailing log context ("failed with 500", stack
 *      frames, next log line) is preserved instead of being eaten into the
 *      REDACTED replacement. A URL embedded in free text takes its query
 *      string and fragment down with it (because neither contains whitespace)
 *      — this is a fail-safe: any sensitive value sitting in a query param
 *      is scrubbed along with the path identifier.
 */
export const PARAM_VALUE_PATTERN = '[^/\\s]+';

/** Maps API directory name to its mount path prefix. */
export const API_MOUNT_PATHS: Record<string, string> = {
  v1: '/api/v1',
  v2: '/api/v2',
  v3: '/api/v3',
  account: '/api/account',
  colonel: '/api/colonel',
  domains: '/api/domains',
  organizations: '/api/organizations',
  invite: '/api/invite',
  incoming: '/api/incoming',
};

/**
 * Parse a `sensitive=` route param value.
 *
 * - Missing/empty string  -> null (route is not sensitive)
 * - Literal 'true'        -> true  (all :params in the path are sensitive)
 * - 'key1,key2'           -> Set<string> of named sensitive params
 */
export function parseSensitiveSpec(
  value: string | undefined
): true | Set<string> | null {
  if (value === undefined || value === null) return null;
  const trimmed = value.trim();
  if (trimmed === '') return null;
  if (trimmed === 'true') return true;
  return new Set(
    trimmed
      .split(',')
      .map((s) => s.trim())
      .filter((s) => s.length > 0)
  );
}

/**
 * Escape regex metacharacters in a literal path segment. Forward slashes are
 * escaped too so the output is safe to embed in a `/.../` JS regex literal.
 */
function escapeRegexLiteral(segment: string): string {
  return segment.replace(/[\\/^$.*+?()[\]{}|]/g, '\\$&');
}

/**
 * Convert a route path with `:param` tokens into a regex pattern string.
 *
 * - When `spec === true`, every `:param` becomes a capture group matching
 *   PARAM_VALUE_PATTERN.
 * - When `spec` is a `Set`, only params listed in the set become capture
 *   groups; other params become non-capturing groups (still matched so the
 *   literal path shape is preserved, but not scrubbed).
 *
 * The result is unanchored. This lets a pattern match a route substring
 * inside a fully-qualified URL or embedded in free-form exception text.
 * Over-scrubbing is an accepted tradeoff: a sibling route with the same
 * static shape but a literal segment in place of a param would see that
 * literal redacted to `[REDACTED]`. Grep has confirmed no such sibling
 * routes exist today.
 *
 * @returns the regex source and the number of capture groups emitted. A
 * zero capture count indicates a dead pattern (nothing to scrub) and
 * callers should treat this as an error — a sensitive route with no
 * scrubbable param is a misconfigured annotation.
 */
export function pathToRegexPattern(
  path: string,
  spec: true | Set<string>
): { regex: string; captureCount: number } {
  let out = '';
  let captureCount = 0;
  let i = 0;

  while (i < path.length) {
    const ch = path[i];
    if (ch === ':') {
      // Read the param name ([A-Za-z_][A-Za-z0-9_]*)
      let j = i + 1;
      while (j < path.length && /\w/.test(path[j])) {
        j++;
      }
      const name = path.slice(i + 1, j);
      const isSensitive = spec === true || spec.has(name);
      if (isSensitive) {
        out += `(${PARAM_VALUE_PATTERN})`;
        captureCount++;
      } else {
        out += `(?:${PARAM_VALUE_PATTERN})`;
      }
      i = j;
    } else {
      out += escapeRegexLiteral(ch);
      i++;
    }
  }

  return { regex: out, captureCount };
}
