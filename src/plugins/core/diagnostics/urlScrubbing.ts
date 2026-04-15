// src/plugins/core/diagnostics/urlScrubbing.ts
//
// Internal utilities for URL scrubbing in Sentry diagnostics.
//
// These functions are exported from this file but NOT re-exported from the
// public barrel (src/plugins/core/index.ts). This pattern allows:
//
// 1. Direct unit tests: Tests import from '@/plugins/core/diagnostics/urlScrubbing'
//    to test edge cases (length-descending sort, hostname protection, deduplication)
//    in isolation without mock infrastructure.
//
// 2. Clean public API: External code imports from '@/plugins/core' and only sees
//    createDiagnostics() and the public scrubbing utilities. These internal helpers
//    are implementation details.
//
// 3. Production code: enableDiagnostics.ts imports from this internal path directly.
//    The wiring is still tested via handler tests that go through createDiagnostics().

import type { RouteMeta } from '@/types/router';

/**
 * Collects param values to redact from route params, sorted by length descending.
 * Sorting ensures longer strings are replaced before shorter ones to avoid
 * corrupting overlapping matches (e.g., 'foobar' before 'foo').
 *
 * @param params - Route params object with values to redact
 * @param paramsToScrub - Which params to scrub: undefined/true = all, string[] = named only
 * @returns Array of values sorted by length descending, ready for scrubbing
 */
export function collectValuesToRedact(
  params: Record<string, string | string[]>,
  paramsToScrub: RouteMeta['sentryScrubParams']
): string[] {
  const valuesToRedact = new Set<string>();

  for (const [name, val] of Object.entries(params)) {
    // Skip if we're only scrubbing specific params and this isn't one of them
    if (Array.isArray(paramsToScrub) && !paramsToScrub.includes(name)) {
      continue;
    }
    const items = Array.isArray(val) ? val : [val];
    for (const item of items) {
      if (item && typeof item === 'string' && item.length > 0) {
        valuesToRedact.add(item);
      }
    }
  }

  // Sort by length descending to replace longer strings first
  return Array.from(valuesToRedact).sort((a, b) => b.length - a.length);
}

/**
 * Scrubs a URL using pre-collected values to redact.
 * Uses URL API to isolate path/query/hash from origin to prevent
 * accidental hostname redaction (e.g., 'one' matching 'onetimesecret.com').
 *
 * @param url - The URL string to scrub
 * @param sortedValues - Values to redact, pre-sorted by length descending
 * @returns The scrubbed URL with sensitive values replaced by [REDACTED]
 */
export function scrubUrlWithValues(url: string, sortedValues: string[]): string {
  if (!url || typeof url !== 'string' || sortedValues.length === 0) {
    return url;
  }

  let result = url;
  try {
    // Protect the origin (protocol/host) from accidental redaction
    const parsed = new URL(url);
    let pathPart = parsed.pathname + parsed.search + parsed.hash;
    for (const val of sortedValues) {
      pathPart = pathPart.split(val).join('[REDACTED]');
    }
    result = parsed.origin + pathPart;
  } catch {
    // Fallback for relative URLs or invalid strings
    for (const val of sortedValues) {
      result = result.split(val).join('[REDACTED]');
    }
  }
  return result;
}
