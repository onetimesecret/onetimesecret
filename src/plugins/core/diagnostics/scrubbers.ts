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
 * Legacy pattern for known sensitive URL paths.
 * Matches path segments that contain tokens or identifiers:
 * - /secret/, /private/, /receipt/, /incoming/ - core secret paths
 * - /invite/ - invitation tokens
 * - /account/email/confirm/ - email confirmation tokens (matched as /account/ then /confirm/)
 *
 * Note: Some auth routes use query params instead of path params:
 * - /reset-password?key=... - handled by query param scrubbing
 * - /verify-account?token=... - handled by query param scrubbing
 *
 * @deprecated Use scrubSensitivePath() from generated patterns instead.
 * Kept as fallback for paths not covered by route-derived patterns.
 *
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

  let result = url;

  // First pass: scrub using generated route-derived patterns
  result = scrubSensitivePath(result);

  // Second pass: fallback for paths not covered by generated patterns
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  // Third pass: scrub any remaining 62-char verifiable IDs
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');

  // Fourth pass: scrub email addresses (e.g., in query params like ?email=user@example.com)
  result = result.replace(EMAIL_PATTERN, '[EMAIL REDACTED]');

  return result;
}
