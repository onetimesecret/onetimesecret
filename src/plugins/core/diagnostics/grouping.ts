// src/plugins/core/diagnostics/grouping.ts
//
// ═══════════════════════════════════════════════════════════════════════════════
// EXPLICIT ISSUE-GROUPING RULES
// ═══════════════════════════════════════════════════════════════════════════════
//
// Sentry's default grouping keys on stack frames, and the frames of a minified
// SPA bundle change with every deploy (`main.Ccws7ZEL` today, `main.DZXtQ8Fc`
// tomorrow). The observed result on the self-hosted instance is the same
// defect fragmenting into a fresh issue per deploy — alert fatigue, broken
// issue history, and "regressed" markers that mean nothing.
//
// `event.fingerprint` is Sentry's grouping key: events carrying the same array
// collapse into ONE issue regardless of stack-frame or bundle-hash churn.
// This module assigns it explicitly for the two families that fragment worst,
// keyed only on values that are stable across users AND deploys:
//
//   Rule A — schema validation failures  -> ['schema-validation', schemaName]
//   Rule B — API request errors          -> ['api-error', method, path, status]
//
// Everything else passes through untouched, keeping Sentry's default grouping
// for events these rules do not understand.
//
// PRIVACY NOTE: nothing volatile and nothing user-specific may enter the
// grouping array. Rule A takes only the schema name (a code identifier); Rule
// B takes the request path only after the same parameterization/scrubbing the
// URL scrubbers apply everywhere else, so a secret identifier can never
// become a grouping key.

import type { ErrorEvent, EventHint } from '@sentry/core';
import { scrubUrlWithPatterns } from './scrubbers';

/**
 * Matches the message family produced by `gracefulParse` in
 * src/utils/schemaValidation.ts:
 *
 *   "Schema validation failed for <SchemaName> — 2 issue(s) [record.foo]: …"
 *
 * Only the schema name is captured. The issue count, field paths, and Zod
 * messages are all volatile (they vary per payload) and must not key the
 * group — the entire point is that one drifted serializer is ONE issue.
 * Messages without the "for <SchemaName>" clause are left to default
 * grouping; there is no schema name to key on.
 */
const SCHEMA_VALIDATION_MESSAGE = /^Schema validation failed for ([\w.$-]+)/;

/**
 * The subset of an HTTP-request-shaped error this module reads.
 *
 * Structural on purpose: mocked axios errors are not `instanceof AxiosError`
 * (see the interceptors specs), and fetch wrappers produce similar shapes, so
 * detection is by the presence of `config.url` — the one property every
 * axios-family error carries — rather than by class.
 *
 * Exported (with `resolveRequestError` and `requestOutcome` below) so the
 * expected-outcome noise filter (expectedOutcomes.ts, #4286) agrees with
 * grouping on what counts as a request-shaped error and what its outcome is,
 * instead of re-deriving both.
 */
export interface RequestErrorLike {
  config?: { url?: unknown; method?: unknown };
  response?: { status?: unknown };
  code?: unknown;
  name?: unknown;
  message?: unknown;
}

/** A request-shaped error together with the URL that proved its shape. */
export interface ResolvedRequestError {
  err: RequestErrorLike;
  url: string;
}

/**
 * Narrows a capture hint's original exception to a request-shaped error, or
 * null when it isn't one (no `config.url` — see `RequestErrorLike`).
 */
export function resolveRequestError(hint: EventHint | undefined): ResolvedRequestError | null {
  const original = hint?.originalException;
  if (!original || typeof original !== 'object') {
    return null;
  }
  const err = original as RequestErrorLike;
  const url = err.config?.url;
  if (typeof url !== 'string' || url.length === 0) {
    return null;
  }
  return { err, url };
}

/**
 * Collects every message-bearing string on the event: the standalone
 * `message` plus each exception value. Linked errors mean the schema message
 * may sit on any of them.
 */
function eventMessages(event: ErrorEvent): string[] {
  const messages: string[] = [];
  if (typeof event.message === 'string') {
    messages.push(event.message);
  }
  for (const exception of event.exception?.values ?? []) {
    if (typeof exception.value === 'string') {
      messages.push(exception.value);
    }
  }
  return messages;
}

/**
 * Rule A: schema validation failures group by schema name.
 *
 * @returns The grouping array, or null when the event is not in the family.
 */
function schemaValidationGroup(event: ErrorEvent): string[] | null {
  for (const message of eventMessages(event)) {
    const match = SCHEMA_VALIDATION_MESSAGE.exec(message);
    if (match) {
      return ['schema-validation', match[1]];
    }
  }
  return null;
}

/**
 * Reduces a request URL to its parameterized, deploy- and user-stable path.
 *
 * Reuses the existing URL scrubbers (route-derived patterns, the sensitive
 * path net, and the verifiable-ID net), so `/api/v2/secret/<62-char-id>` and
 * `/receipt/<id>` collapse to the same `[REDACTED]`-parameterized path for
 * every user. The query string and fragment are dropped entirely — they are
 * volatile and never part of the route identity.
 */
function normalizeRequestPath(url: string): string {
  let pathname: string;
  try {
    // Synthetic base so bare paths parse; only the parser is used.
    pathname = new URL(url, 'http://_').pathname;
  } catch {
    pathname = url.split(/[?#]/)[0];
  }
  return scrubUrlWithPatterns(pathname);
}

/**
 * Rule B: API request errors group by method + parameterized path + outcome.
 *
 * The outcome component is the HTTP status when the server answered, else a
 * coarse failure class:
 *   - 'timeout' — the request ran past its deadline with no response.
 *   - 'aborted' — the request was cancelled (unmount, navigation away, tab
 *     close); axios signals this via ERR_CANCELED/CanceledError/ECONNABORTED,
 *     the fetch path via AbortError.
 *   - 'network' — no response at all (offline, DNS, CORS, connection reset).
 *   - the error class name as a last resort, so an unrecognized failure mode
 *     still groups by route rather than by stack frame.
 *
 * 'timeout' and 'aborted' are deliberately separate classes, not one bucket:
 * an abort is the user leaving and is dropped as expected noise, while a
 * timeout is the API failing to answer and must reach Sentry. See
 * ABORT_MARKERS below and expectedOutcomes.ts.
 *
 * @returns The grouping array, or null when the hint does not carry a
 *   request-shaped error.
 */
function apiErrorGroup(hint: EventHint | undefined): string[] | null {
  const resolved = resolveRequestError(hint);
  if (!resolved) {
    // Not a request-shaped error — no config.url, no route to group by.
    return null;
  }

  return [
    'api-error',
    requestMethod(resolved.err),
    normalizeRequestPath(resolved.url),
    requestOutcome(resolved.err),
  ];
}

/** Uppercased HTTP method; axios stores it lowercase and defaults to GET. */
function requestMethod(err: RequestErrorLike): string {
  const method = err.config?.method;
  return typeof method === 'string' && method.length > 0 ? method.toUpperCase() : 'GET';
}

/**
 * Marker values (axios `code` / error `name`) for a request that ran past its
 * deadline. Checked BEFORE the abort markers, because the two overlap on the
 * wire unless the client asks them not to.
 *
 * `ETIMEDOUT` is what axios reports for a timeout when
 * `transitional.clarifyTimeoutError` is set — src/api/index.ts sets it on the
 * shared client for exactly this reason. `TimeoutError` is the DOMException
 * name from the fetch path (`AbortSignal.timeout()`).
 */
const TIMEOUT_MARKERS = new Set(['ETIMEDOUT', 'TimeoutError']);

/**
 * Marker values (axios `code` / error `name`) for a CANCELLED request — torn
 * down before a response arrived, by the caller or by the browser.
 *
 * `ECONNABORTED` sits here rather than with the timeouts on purpose, and the
 * distinction is load-bearing: axios uses that one code for both
 * `xhr.onabort` (navigation away, tab close) AND, by default, `xhr.ontimeout`.
 * Left ambiguous, dropping 'aborted' as expected noise would also swallow
 * every timed-out request during an API slowdown. src/api/index.ts resolves
 * the ambiguity at the source with `transitional.clarifyTimeoutError`, so a
 * timeout arrives as ETIMEDOUT and ECONNABORTED means abort and only abort.
 *
 * Do not "fix" this by removing ECONNABORTED: on the XHR adapter it is the
 * ONLY code an actual abort produces, so dropping it would stop the
 * navigate-away case from ever being recognized.
 */
const ABORT_MARKERS = new Set(['ERR_CANCELED', 'ECONNABORTED', 'CanceledError', 'AbortError']);

/** Derives the outcome component: status, else a coarse failure class. */
export function requestOutcome(err: RequestErrorLike): string {
  const status = err.response?.status;
  if (typeof status === 'number') {
    return String(status);
  }
  if (TIMEOUT_MARKERS.has(err.code as string) || TIMEOUT_MARKERS.has(err.name as string)) {
    return 'timeout';
  }
  if (ABORT_MARKERS.has(err.code as string) || ABORT_MARKERS.has(err.name as string)) {
    return 'aborted';
  }
  if (err.code === 'ERR_NETWORK' || err.message === 'Network Error') {
    return 'network';
  }
  return typeof err.name === 'string' && err.name.length > 0 ? err.name : 'error';
}

/**
 * Applies the explicit grouping rules to an outbound error event, in place.
 *
 * Composed into `beforeSend` in enableDiagnostics.ts AFTER the scrubbers —
 * the rules read only the schema name and the parameterized path, so order
 * does not change the group, but running last keeps this module a pure
 * consumer of the already-scrubbed event.
 *
 * An event that already carries an explicit grouping array (set upstream via
 * `captureException` scope options) is respected and left alone. Events
 * matching neither rule are returned untouched so Sentry's default grouping
 * still applies to them.
 *
 * @param event - The outbound error event (mutated in place).
 * @param hint - Sentry's capture hint; `originalException` carries the raw
 *   error whose request metadata Rule B reads.
 */
export function applyGroupingRules(event: ErrorEvent, hint?: EventHint): void {
  // `fingerprint` is Sentry's grouping key — the one field that overrides
  // stack-frame grouping. This assignment (and this comment) are the only
  // places the term appears; everything callable here says "grouping".
  if (event.fingerprint !== undefined) {
    return;
  }

  const group = schemaValidationGroup(event) ?? apiErrorGroup(hint);
  if (group) {
    event.fingerprint = group;
  }
}
