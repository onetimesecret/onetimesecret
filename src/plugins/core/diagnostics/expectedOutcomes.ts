// src/plugins/core/diagnostics/expectedOutcomes.ts
//
// Drops Sentry events for request-shaped errors whose outcome is the product
// working as designed, not a defect (#4286 — 474 events across ~35 issues,
// the largest cluster in the frontend Sentry project):
//
//   - 404 — the resource was already consumed. On `/secret/:id` this is a
//     secret that was already viewed, burned, or expired; the same holds for
//     any other identifier-addressed resource. HTTP_STATUS_CODES.HUMAN (see
//     src/schemas/errors/constants.ts) already keeps 404 out of Sentry for
//     errors that flow through the app's own error handlers (useAsyncHandler,
//     globalErrorBoundary) — this is the SAME rule enforced one layer
//     further out, in beforeSend, which every event reaches regardless of
//     path. That makes it a backstop, not a second policy: an event dropped
//     here would already have been dropped by those handlers if it had gone
//     through them.
//   - 'aborted' — the user navigated away or closed the tab mid-request
//     (axios ERR_CANCELED/CanceledError/ECONNABORTED, fetch AbortError).
//   - 'network' — no response at all (offline, DNS, client-side connection
//     failure) — not something the API did.
//
// Deliberately narrow: every other outcome, 5xx included, keeps reporting.
// A 502/503/520 is OUR failure (deploy, upstream outage), not the client's
// or the product's, and must not be swallowed by this list — see
// requestOutcome() in grouping.ts, which only returns 'network' when there
// is no response at all, never for a response that carries a status.

import type { EventHint } from '@sentry/core';

import { requestOutcome, resolveRequestError } from './grouping';

/**
 * Outcomes (see `requestOutcome` in grouping.ts) that represent an expected
 * transport result rather than a defect.
 *
 * @internal Exported for testing
 */
export const EXPECTED_TRANSPORT_OUTCOMES: ReadonlySet<string> = new Set([
  'aborted',
  'network',
  '404',
]);

/**
 * True when the event's original exception is a request-shaped error (see
 * `resolveRequestError`) whose outcome is expected noise that should never
 * reach Sentry.
 *
 * Consumed by beforeSend BEFORE grouping/scrubbing run (enableDiagnostics.ts)
 * — there is no point fingerprinting or redacting an event that is about to
 * be dropped.
 *
 * @internal Exported for testing
 */
export function isExpectedTransportOutcome(hint: EventHint | undefined): boolean {
  const resolved = resolveRequestError(hint);
  return resolved !== null && EXPECTED_TRANSPORT_OUTCOMES.has(requestOutcome(resolved.err));
}
