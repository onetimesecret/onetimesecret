// src/utils/pii.ts

/**
 * Personally-identifiable data helpers.
 *
 * The guiding rule this module encodes: PII must never travel in a URL query
 * string. A URL leaks out of the application through browser history, bfcache,
 * the `Referer` header, proxy/CDN access logs and Sentry breadcrumbs — none of
 * which the app controls. See docs/specs/recipient-disclosure/recipient-disclosure-matrix.html
 * (finding F6, "The URL is the bearer secret — and it leaks") and the
 * "Query-string policy" section of src/router/README.md.
 *
 * When a value like an email address must reach the next page, hand it over via
 * router history `state` (invisible to the URL) instead of the query.
 *
 * This module is intentionally dependency-free (no Vue/Pinia/Sentry imports) so
 * it can be shared by the runtime navigation guard, the custom ESLint rule and
 * the diagnostics tests alike.
 */

/**
 * Query keys that carry PII and must not appear in a URL. Keep this list in
 * sync with the copy embedded in src/build/eslint/no-pii-in-query.ts (that rule
 * runs at lint time and cannot resolve the `@/` alias).
 */
export const PII_QUERY_KEYS = ['email', 'password', 'token', 'key', 'code'] as const;

export type PiiQueryKey = (typeof PII_QUERY_KEYS)[number];

/** Maximum length of a valid email address (RFC 5321 §4.5.3.1.3). */
export const MAX_EMAIL_LENGTH = 254;

/**
 * Gate an email value for display. Returns the value only if it is a plausible
 * address to show, otherwise ''.
 *
 * This is deliberately NOT a validator — it is a display guard. It rejects
 * non-strings, empty and over-long input, and anything without an '@', so a
 * hand-crafted `?email=<junk>` (or a tampered history-state value) degrades to
 * the generic "check your email" copy instead of rendering attacker-controlled
 * text verbatim. Vue already escapes interpolation, so this is defense in depth
 * against nonsense, not against XSS.
 */
export function sanitizeDisplayEmail(value: unknown): string {
  if (typeof value !== 'string') return '';
  if (value.length === 0 || value.length > MAX_EMAIL_LENGTH) return '';
  return value.includes('@') ? value : '';
}

/**
 * Names of any PII keys present (with a non-empty value) in a route query.
 * Used by the dev-time navigation guard to warn when PII is about to ride in a
 * URL. Array-valued query params (e.g. `?email[]=a&email[]=b`) count as present.
 */
export function findPiiQueryKeys(
  query: Record<string, unknown> | null | undefined
): PiiQueryKey[] {
  if (!query) return [];
  return PII_QUERY_KEYS.filter((key) => {
    const value = query[key];
    if (value == null) return false;
    if (Array.isArray(value)) return value.some((v) => v != null && v !== '');
    return value !== '';
  });
}
