// src/plugins/core/diagnostics/scrubbers.ts
//
// Dependency-free utilities for scrubbing sensitive data from strings and URLs.
// Extracted from enableDiagnostics.ts to avoid pulling in Sentry/Vue dependencies.
//
// Used by:
// - axios interceptors (breadcrumb scrubbing)
// - Sentry beforeBreadcrumb handler
// - Sentry beforeSend handler

import { scrubSensitivePath } from '@/generated/sentry-scrub-patterns';

/**
 * Legacy fallback pattern for sensitive URL paths.
 *
 * Current approach uses deterministic route metadata (fail-safe, opt-out):
 * - Frontend: src/routes/index.ts route definitions with scrub metadata
 * - Backend: Otto routes with `sensitive=true` annotation, e.g.:
 *   `GET /receipt/:identifier ... sensitive=true`
 *
 * This regex catches paths missed by route-derived patterns:
 * - /secret/, /private/, /receipt/, /incoming/ - core secret paths
 * - /invite/ - invitation tokens
 * - /confirm/ - email confirmation tokens
 *
 * @see scrubSensitivePath - generated patterns from route metadata
 * @see src/generated/sentry-scrub-patterns.ts - generated output
 * @internal Exported for testing
 */
export const SENSITIVE_PATH_PATTERN =
  /\/(secret|private|receipt|incoming|invite|confirm)\/([a-zA-Z0-9]+)/gi;

/**
 * Fallback pattern for 62-character verifiable identifiers.
 * These are base62-encoded IDs that could appear in unexpected paths.
 *
 * @internal Exported for testing
 */
export const VERIFIABLE_ID_PATTERN = /[0-9a-z]{62}/gi;

/**
 * Pattern for email addresses.
 * Matches standard email formats like user@example.com.
 *
 * @internal Exported for testing
 */
export const EMAIL_PATTERN = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;

/**
 * Scrubs sensitive data from arbitrary strings using regex patterns.
 * Used for exception messages, standalone messages, and other text.
 *
 * Scrubs:
 * - Email addresses -> [EMAIL REDACTED]
 * - 62-char verifiable IDs -> [REDACTED]
 * - Sensitive path patterns -> /type/[REDACTED]
 *
 * @param text - The string to scrub
 * @returns The scrubbed string with sensitive data replaced
 */
export function scrubSensitiveStrings(text: string): string {
  if (!text || typeof text !== 'string') {
    return text;
  }

  let result = text;

  // Scrub email addresses
  result = result.replace(EMAIL_PATTERN, '[EMAIL REDACTED]');

  // Scrub 62-char verifiable IDs
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');

  // Scrub sensitive path patterns using generated route-derived patterns
  result = scrubSensitivePath(result);

  // Fallback: scrub any remaining sensitive paths not covered by generated patterns
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  return result;
}

/**
 * Apply anchored generated patterns to the pathname portion of a URL.
 *
 * The generated patterns in `sentry-scrub-patterns.ts` are anchored with `^`/`$`
 * so that they only match a bare pathname (e.g. `/api/v3/secret/<id>`), not a
 * full URL like `https://host/api/v3/secret/<id>?q=1`. Sentry breadcrumbs pass
 * full absolute URLs, while axios interceptors pass bare paths — so we always
 * parse the input through `URL` (using a synthetic base for bare paths) to
 * normalize away the query/fragment before invoking the anchored patterns.
 */
function extractAndScrubPath(input: string): string {
  try {
    // Use a synthetic base so bare paths (e.g. /api/v1/secret/abc?foo=bar)
    // parse cleanly. The base is discarded when reassembling — we only use
    // its parser. Detect "had host" by checking the raw input for a protocol
    // prefix, since `new URL('/p', 'http://_')` yields host `_` which we must
    // not echo back.
    //
    // Protocol-relative URLs (`//host/path`) are detected alongside
    // fully-qualified URLs so the host is preserved during reassembly.
    // Removing the `startsWith('//')` branch would cause such URLs to
    // silently drop their host. Adding it must also preserve the `//`
    // prefix on output (do not echo back the synthetic `http:` scheme
    // from the base URL).
    //
    // data: URIs (`data:text/plain,foo`) are not a real Sentry breadcrumb
    // input shape and are not accounted for. Under current logic they
    // would have their scheme stripped because the scheme regex requires
    // `://`.
    const isProtocolRelative = input.startsWith('//');
    const isFullURL = /^[a-z][a-z0-9+.-]*:\/\//i.test(input);
    const hadHost = isProtocolRelative || isFullURL;
    const parsed = new URL(input, 'http://_');
    const scrubbedPath = scrubSensitivePath(parsed.pathname);
    if (!hadHost) return scrubbedPath + parsed.search + parsed.hash;
    const prefix = isProtocolRelative ? '//' : parsed.protocol + '//';
    return prefix + parsed.host + scrubbedPath + parsed.search + parsed.hash;
  } catch {
    // Fallback for genuinely malformed inputs (e.g. control chars that the
    // URL parser rejects even with a base).
    return scrubSensitivePath(input);
  }
}

/**
 * Scrubs sensitive identifiers from a URL path using regex patterns.
 * Used for HTTP breadcrumbs where we don't have route context.
 *
 * Scrubs:
 * - Known sensitive paths (/secret/, /private/, /receipt/, /incoming/, /invite/, /confirm/)
 * - 62-char verifiable IDs
 * - Email addresses in query strings (e.g., ?email=user@example.com)
 *
 * @param url - The URL string to scrub
 * @returns The scrubbed URL with sensitive identifiers replaced by [REDACTED]
 */
export function scrubUrlWithPatterns(url: string): string {
  if (!url || typeof url !== 'string') {
    return url;
  }

  // First pass: scrub using generated route-derived patterns. The generated
  // patterns are anchored, so we must apply them to the pathname only — full
  // absolute URLs (from Sentry fetch/xhr breadcrumbs) would otherwise never
  // match.
  let result = extractAndScrubPath(url);

  // Second pass: fallback for paths not covered by generated patterns
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  // Third pass: scrub any remaining 62-char verifiable IDs
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');

  // Fourth pass: scrub email addresses (e.g., in query params like ?email=user@example.com)
  result = result.replace(EMAIL_PATTERN, '[EMAIL REDACTED]');

  return result;
}
