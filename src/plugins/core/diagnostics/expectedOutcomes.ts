// src/plugins/core/diagnostics/expectedOutcomes.ts
//
// Drops Sentry events for request-shaped errors whose outcome is the product
// working as designed, not a defect (#4286 — 474 events across ~35 issues,
// the largest cluster in the frontend Sentry project).
//
// EVERY RULE HERE IS SCOPED, and that is the whole design. A flat "drop these
// outcomes" list is cheap to write and expensive to own: the same outcome
// that is noise on one route is the only evidence of an outage on another,
// and a filter that cannot tell them apart takes the outage down with the
// noise. So each outcome carries the condition that makes it expected:
//
//   404       — only on an identifier-addressed secret/receipt route, where
//               it means the resource was already viewed, burned, or expired.
//               A 404 anywhere else is a routing defect (a mis-versioned or
//               renamed endpoint, a typo in a path) and MUST stay visible;
//               those are exactly the regressions Sentry is for.
//   'aborted' — always. The request was cancelled: the user navigated away or
//               closed the tab mid-request. Never a timeout — the two share a
//               code on the wire, and src/api/index.ts separates them at the
//               source so this rule can be unconditional. See ABORT_MARKERS
//               and TIMEOUT_MARKERS in grouping.ts.
//   'network' — only while the browser reports itself OFFLINE. An ERR_NETWORK
//               raised while the client believes it is online is DNS, TLS,
//               CORS, or an unreachable deployment — ours, and reportable.
//
// Everything else keeps reporting, 5xx and 'timeout' included: a 502/503/520
// or a request that ran past its deadline is OUR failure, not the client's.
// Those already fan out into one issue per status/method/path through the
// `apiErrorGroup` fingerprinting in grouping.ts, so keeping them costs issue
// volume, not issue clarity.
//
// Layering note: HTTP_STATUS_CODES.HUMAN (src/schemas/errors/constants.ts)
// already keeps 404 out of Sentry for errors that flow through the app's own
// handlers (useAsyncHandler, globalErrorBoundary). This module is the same
// policy enforced one layer further out, in beforeSend, which every event
// reaches regardless of the path that produced it — a backstop for manual
// captureException calls, unhandled rejections, and integration auto-captures.

import type { EventHint } from '@sentry/core';

import { requestOutcome, resolveRequestError } from './grouping';

/**
 * A path segment that is a verifiable identifier.
 *
 * MIRROR — the shape is VERIFIABLE_ID_PATTERN in ./scrubbers.ts: 62-char
 * base-36 IDs (v0.24+) and legacy 31-char IDs (v0.23). Restated here anchored
 * to a WHOLE segment and without the `g` flag, deliberately rather than
 * imported:
 *   - `.test()` on a `g`-flagged regex is stateful (it advances `lastIndex`),
 *     which makes the shared constant unusable as a predicate.
 *   - A substring match would defeat the point. `/secret/conceal` has to fail
 *     this check; a loose `[^/]+` segment match would classify the conceal
 *     endpoint as an identifier route and hide its 404s.
 * Keep the two in step if the identifier width ever changes.
 */
const IDENTIFIER_SEGMENT = /^(?:[0-9a-z]{62}|[0-9a-z]{31})$/i;

/**
 * Resources addressed by a verifiable identifier — the consumable ones, where
 * a 404 is the expected steady state rather than a defect. Both are one-shot:
 * once viewed, burned, or expired, the record is gone by design.
 */
const IDENTIFIED_RESOURCES = new Set(['secret', 'receipt']);

/**
 * Sub-actions on an identified resource that share its 404 semantics
 * (`/secret/:id/reveal`, `/receipt/:id/burn`). Enumerated, not `[a-z]+`, so a
 * new action has to be considered rather than inheriting the drop silently.
 */
const IDENTIFIED_RESOURCE_ACTIONS = new Set(['reveal', 'burn']);

/**
 * True when the URL addresses a specific secret or receipt by identifier —
 * `/secret/:id`, `/secret/:id/reveal`, `/receipt/:id`, `/receipt/:id/burn` —
 * and therefore a 404 means "already consumed", not "endpoint missing".
 *
 * Matched from the END of the path so it stays independent of the API prefix
 * (`/api/v3`, `/api/v3/guest`, or whatever replaces them); the resource word
 * sits immediately before the identifier and any action immediately after.
 *
 * @internal Exported for testing
 */
export function isIdentifierAddressedResource(url: string): boolean {
  let pathname: string;
  try {
    // Synthetic base so bare paths parse; only the parser is used.
    pathname = new URL(url, 'http://_').pathname;
  } catch {
    pathname = url.split(/[?#]/)[0];
  }

  const segments = pathname.split('/').filter((segment) => segment.length > 0);
  const last = segments.length - 1;
  const idIndex = IDENTIFIED_RESOURCE_ACTIONS.has(segments[last]?.toLowerCase())
    ? last - 1
    : last;

  // idIndex < 1 leaves no room for the resource word that must precede it.
  if (idIndex < 1) {
    return false;
  }

  return (
    IDENTIFIER_SEGMENT.test(segments[idIndex]) &&
    IDENTIFIED_RESOURCES.has(segments[idIndex - 1].toLowerCase())
  );
}

/**
 * True when the browser reports no connectivity.
 *
 * `navigator.onLine` is only trustworthy in the negative — `false` means
 * there is no network interface at all, while `true` merely means one exists
 * (a captive portal or dead upstream still reads as online). That asymmetry
 * is exactly what this rule needs: it drops only on the trustworthy answer
 * and reports on the ambiguous one, so a client-side connectivity blip is
 * silent while a reachability failure the client cannot explain is not.
 */
function isClientOffline(): boolean {
  return typeof navigator !== 'undefined' && navigator.onLine === false;
}

/**
 * True when the event's original exception is a request-shaped error (see
 * `resolveRequestError`) whose outcome is expected noise that should never
 * reach Sentry.
 *
 * Consumed by beforeSend BEFORE grouping/scrubbing run (enableDiagnostics.ts)
 * — there is no point fingerprinting or redacting an event that is about to
 * be dropped.
 *
 * The switch is exhaustive on purpose: an outcome with no case here reports.
 * New failure classes must be added deliberately, never inherit a drop.
 */
export function isExpectedTransportOutcome(hint: EventHint | undefined): boolean {
  const resolved = resolveRequestError(hint);
  if (resolved === null) {
    return false;
  }

  switch (requestOutcome(resolved.err)) {
    case 'aborted':
      return true;
    case 'network':
      return isClientOffline();
    case '404':
      return isIdentifierAddressedResource(resolved.url);
    default:
      return false;
  }
}
