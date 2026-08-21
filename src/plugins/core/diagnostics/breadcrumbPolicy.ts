// src/plugins/core/diagnostics/breadcrumbPolicy.ts
//
// ═══════════════════════════════════════════════════════════════════════════════
// BREADCRUMBS ARE METADATA-ONLY
// ═══════════════════════════════════════════════════════════════════════════════
//
// A breadcrumb answers "what happened just before the error", not "what was in
// it". This module enforces that distinction structurally, with per-category
// key ALLOWLISTS rather than denylists.
//
// ── Why allowlist and not denylist ────────────────────────────────────────────
//
// `breadcrumb.data` is an open `Record<string, unknown>` written by several
// independent producers: Sentry's own fetch/xhr instrumentation, its DOM and
// history instrumentation, our axios interceptors, and any `addBreadcrumb()`
// call anywhere in the app or in a vendored dependency. A denylist has to
// enumerate every bad key that exists TODAY and stays correct only until the
// next SDK minor, the next interceptor, or the next `addBreadcrumb` call adds
// one. An allowlist is correct by default for keys that do not exist yet, which
// is precisely the population we cannot review.
//
// Concretely: @sentry/browser's fetch instrumentation already puts
// `request_body_size` / `response_body_size` in `data`, and enabling
// `networkDetailAllowUrls` on any future integration would add
// `request.body` / `response.body` / `request.headers` alongside them. Under a
// denylist those arrive live; under this allowlist they are dropped before the
// breadcrumb is ever stored.
//
// ── The retained set (HTTP breadcrumbs) ───────────────────────────────────────
//
//   url                — already scrubbed by the two-layer URL scrubber before
//                        it reaches here (route-param values + pattern net)
//   method             — GET/POST/…; carries nothing about the payload
//   status_code        — numeric HTTP status
//   duration           — milliseconds; timing only
//   request_body_size  — BYTE COUNT of the request body
//   response_body_size — BYTE COUNT of the response body
//   trace_id           — W3C/Sentry trace correlation id, generated client-side
//   span_id            — span correlation id, generated client-side
//   request_id         — server-issued correlation id (an opaque request handle,
//                        NOT a session, account, or secret identifier)
//
// ── On the two *_body_size keys (deliberate policy change) ────────────────────
//
// These were dropped in an earlier pass by proximity: they sit next to
// `request_body` / `response_body` in @sentry/browser's fetch instrumentation
// and share a name prefix with them. A NUMBER OF BYTES IS NOT CONTENT. It
// cannot be reversed into a payload, it carries no personal data at any size,
// and it answers the first question anyone asks about a schema failure: was the
// response EMPTY, TRUNCATED, or full-size-but-wrong-shape? Those three have the
// same status code and completely different causes. Dropping them cost the
// operator that distinction and bought nothing back — a data-minimization
// control that removes no data is pure loss.
//
// The bodies themselves (`request_body`, `response_body`) remain refused, which
// is the control that was actually doing the work.
//
// "A number of bytes" is now enforced rather than assumed: every allowlisted
// key declares a primitive type and a value of any other type is dropped (see
// BREADCRUMB_DATA_KEY_TYPES). Before that, a producer writing
// `request_body_size: '{"password":"hunter2"}'` shipped it verbatim — the
// claim was a property of @sentry/browser's typings, not of this module.
//
// ── On `duration` ─────────────────────────────────────────────────────────────
//
// @sentry/browser does NOT put timing in `breadcrumb.data`; it puts
// `startTimestamp` / `endTimestamp` in the breadcrumb HINT. So allowlisting
// `duration` retained a key no producer in this app writes — an entry that
// documented an intent it did not implement. It is kept in the allowlist (a
// hand-written `addBreadcrumb` may supply it, and it is metadata either way)
// and is now actually POPULATED from the hint by
// {@link httpBreadcrumbDurationFromHint}, so the timing the comment always
// promised is really on the wire.
//
// ── The refused set (ON THE TWO ALLOWLISTED CATEGORIES) ───────────────────────
//
//   request bodies · response bodies · Authorization headers · any headers at
//   all · cookies · emails · tokens · passphrases · raw route identifiers ·
//   query-string values · form fields · anything not named above
//
// Scope that heading literally: structural allowlisting is applied to `xhr` /
// `fetch` and to `navigation`, and to nothing else. Every OTHER category
// (console, ui.click, ui.input, history, sentry.*) keeps its `data` bag intact
// — see the "All other categories" note in enableDiagnostics.ts, which explains
// why blanket-dropping it would gut ui.click/history diagnostics for no privacy
// gain. Those categories are covered by the free-text pass below (message
// scrubbing everywhere, `data.arguments` dropped on console) and by nothing
// structural, so a producer that writes a header bag onto a `ui.click`
// breadcrumb is NOT refused by this module. No such producer exists today; if
// one appears, it needs its own allowlist entry rather than a wider reading of
// this list.
//
// ── Free-text fields ──────────────────────────────────────────────────────────
//
// `breadcrumb.message` is free text on EVERY category and was previously passed
// through untouched. Console breadcrumbs interpolate arbitrary arguments into
// it (`console.warn('failed for', user.email)`), and DOM breadcrumbs put
// element text and selectors there. It now goes through `scrubSensitiveStrings`
// for every category, which nets emails and verifiable identifiers by shape.
//
// `data.arguments` on console breadcrumbs is the raw argument list — the single
// richest leak surface in the whole breadcrumb pipeline, since it can hold
// whole request/response objects. It is dropped outright, not scrubbed:
// structured scrubbing of arbitrary nested objects is not a thing this codebase
// can guarantee, and the message (scrubbed) already carries the diagnostic
// signal.
//
// Note on production reach: `dropConsole: true` in the rolldown minifier
// removes our own `console.*` calls from production bundles, so in prod the
// console-breadcrumb surface is limited to vendored code. In dev it is wide
// open. The scrubbing applies in both — dev sessions reach Sentry too whenever
// a developer runs against a real DSN.

import type { Breadcrumb } from '@sentry/core';

import { scrubSensitiveStrings } from './scrubbers';

/**
 * Keys retained on `data` for `xhr` / `fetch` breadcrumbs.
 *
 * Every entry here is either timing, a status code, an HTTP verb, an
 * already-scrubbed URL, or a correlation id minted for tracing. Nothing in this
 * set can carry request/response content.
 *
 * @see the module header for the rationale behind each entry.
 */
export const HTTP_BREADCRUMB_DATA_KEYS = [
  'url',
  'method',
  'status_code',
  'duration',
  'request_body_size',
  'response_body_size',
  'trace_id',
  'span_id',
  'request_id',
] as const;

/**
 * Keys retained on `data` for `navigation` breadcrumbs.
 *
 * Sentry's history instrumentation emits exactly `{ from, to }`; both are URLs
 * and both have already been through the two-layer scrubber by the time this
 * allowlist runs. Anything else appearing on a navigation breadcrumb came from
 * somewhere unreviewed and is dropped.
 */
export const NAVIGATION_BREADCRUMB_DATA_KEYS = ['from', 'to'] as const;

/**
 * The TYPE each allowlisted key is permitted to carry.
 *
 * A key-only allowlist made the module header's central claim — "A NUMBER OF
 * BYTES IS NOT CONTENT" — a property of the PRODUCER rather than of this code.
 * It held because @sentry/browser types `request_body_size` /
 * `response_body_size` as `number`; it did not hold structurally, and
 * `{ request_body_size: '{"password":"hunter2"}' }` passed through unchanged.
 * `breadcrumb.data` is an open `Record<string, unknown>` written by several
 * producers, so "the SDK types it as a number" is a bet on every current and
 * future one of them.
 *
 * With this map the claim is enforced: a size is a number or it is dropped, a
 * URL is a string or it is dropped. Values are still `unknown` at the type
 * level, so the check is a runtime `typeof`, which is exactly where the bet
 * used to live.
 *
 * A mistyped value is DROPPED rather than coerced or stringified: a producer
 * that puts a payload where a byte count belongs has already lost the
 * diagnostic, and stringifying it would ship the very content the drop exists
 * to refuse. Every key here is a primitive by contract; nothing in the
 * allowlist is legitimately an object or an array.
 */
const BREADCRUMB_DATA_KEY_TYPES: Record<string, 'string' | 'number'> = {
  url: 'string',
  method: 'string',
  status_code: 'number',
  duration: 'number',
  request_body_size: 'number',
  response_body_size: 'number',
  trace_id: 'string',
  span_id: 'string',
  request_id: 'string',
  from: 'string',
  to: 'string',
};

/**
 * Reduces an open data bag to the allowlisted keys, TYPE-CHECKED.
 *
 * Two independent gates, both required to keep a key:
 *   1. the key appears in `allowed` (the per-category allowlist), and
 *   2. its value has the primitive type that key declares in
 *      {@link BREADCRUMB_DATA_KEY_TYPES}.
 *
 * A key with no declared type is kept on the allowlist's word alone — that is
 * the caller's decision to make, and no such key exists today.
 *
 * Absent keys are NOT materialized as `undefined` — the returned object has
 * only the keys that were actually present, so a breadcrumb that carried
 * `{ method, status_code }` still deep-equals `{ method, status_code }`
 * afterwards. Returns `undefined` when nothing survives, so an emptied bag is
 * dropped rather than shipped as `data: {}`.
 *
 * @param data - The breadcrumb's `data` bag, possibly undefined.
 * @param allowed - The allowlist for this breadcrumb category.
 * @returns A new object containing only allowlisted, present, correctly typed keys.
 */
export function pickAllowedData(
  data: Record<string, unknown> | undefined,
  allowed: readonly string[]
): Record<string, unknown> | undefined {
  if (!data) {
    return undefined;
  }
  const picked: Record<string, unknown> = {};
  for (const key of allowed) {
    if (!Object.hasOwn(data, key)) continue;
    const value = data[key];
    const declared = BREADCRUMB_DATA_KEY_TYPES[key];
    if (declared && typeof value !== declared) continue;
    picked[key] = value;
  }
  return Object.keys(picked).length > 0 ? picked : undefined;
}

/**
 * Milliseconds elapsed for an xhr/fetch breadcrumb, read from its HINT.
 *
 * @sentry/browser's fetch and xhr instrumentation passes
 * `{ startTimestamp, endTimestamp }` (epoch milliseconds) on the SECOND
 * argument to `beforeBreadcrumb`, never inside `breadcrumb.data`. Timing is
 * pure metadata — no body, no header, no identifier — and "did this call take
 * 30ms or 30s before the shape check failed?" separates a slow/partial
 * response from a genuine contract drift.
 *
 * Returns `undefined` unless both endpoints are finite numbers and the
 * interval is non-negative, so a malformed hint degrades to "no timing"
 * rather than to a nonsense number.
 *
 * @param hint - The breadcrumb hint, whatever the SDK handed us.
 * @returns Elapsed milliseconds, or `undefined` when not derivable.
 */
export function httpBreadcrumbDurationFromHint(hint: unknown): number | undefined {
  if (!hint || typeof hint !== 'object') return undefined;
  const { startTimestamp, endTimestamp } = hint as {
    startTimestamp?: unknown;
    endTimestamp?: unknown;
  };
  if (typeof startTimestamp !== 'number' || !Number.isFinite(startTimestamp)) return undefined;
  if (typeof endTimestamp !== 'number' || !Number.isFinite(endTimestamp)) return undefined;
  const elapsed = endTimestamp - startTimestamp;
  return elapsed >= 0 ? elapsed : undefined;
}

/**
 * Applies the free-text policy that holds for EVERY breadcrumb category,
 * whatever else the category-specific handling does.
 *
 * 1. `message` — run through `scrubSensitiveStrings` (emails, 62/31-char
 *    verifiable identifiers). This is the catch-all for console output, DOM
 *    element text, and any hand-written `addBreadcrumb({ message })`.
 * 2. `data.arguments` — dropped for console breadcrumbs. See the module header
 *    for why this is a drop rather than a scrub.
 *
 * Mutates in place; the breadcrumb identity is preserved so callers can keep
 * returning the same object.
 *
 * @param breadcrumb - The breadcrumb to sanitize.
 */
export function applyFreeTextPolicy(breadcrumb: Breadcrumb): void {
  if (typeof breadcrumb.message === 'string') {
    breadcrumb.message = scrubSensitiveStrings(breadcrumb.message);
  }

  if (breadcrumb.category === 'console' && breadcrumb.data && 'arguments' in breadcrumb.data) {
    delete breadcrumb.data.arguments;
    if (Object.keys(breadcrumb.data).length === 0) {
      delete breadcrumb.data;
    }
  }
}
