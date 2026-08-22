// src/plugins/core/enableDiagnostics.ts
//
// ═══════════════════════════════════════════════════════════════════════════════
// THE DIAGNOSTICS BOUNDARY (Sentry wiring)
// ═══════════════════════════════════════════════════════════════════════════════
//
// REFERENCE: docs/architecture/diagnostics-privacy-boundary.md
//
// This module constructs the browser Sentry client and installs the three
// handlers that everything this app reports passes through on the way out:
// `beforeSend` (errors), `beforeSendTransaction` (performance events) and
// `beforeBreadcrumb` (capture-time breadcrumbs).
//
// THIS SUBSYSTEM IS DIAGNOSTICS, NOT ANALYTICS AND NOT METRICS. It exists so a
// defect can be traced back to the code and the endpoint that produced it. It
// does not measure usage, count events for reporting, or profile behaviour, and
// no field emitted from here is read for any of those purposes. That framing is
// what settles the recurring trade-off in the comments below: a field earns its
// place by making a defect diagnosable, and pays for itself only if it carries
// no personal data — so a byte count stays and a request body does not.
//
// LAYER RULE: this directory is SENTRY WIRING. The pure policy it composes —
// scrubbers, URL scrubbing, the schema-issue projection, the route/ref
// registries — lives under src/utils/diagnostics/ and knows nothing about
// Sentry. The two modules that stay here (diagnostics/actorIdentity.ts,
// diagnostics/breadcrumbPolicy.ts) do so because they speak Sentry's own types.

import { getBootstrapValue } from '@/services/bootstrap.service';
import { initDiagnostics } from '@/services/diagnostics.service';
import type { DiagnosticsConfig } from '@/types/diagnostics';
import type { RouteMeta } from '@/types/router';
import { DEBUG } from '@/utils/debug';
import {
  BrowserClient,
  Scope,
  breadcrumbsIntegration,
  browserApiErrorsIntegration,
  dedupeIntegration,
  defaultStackParser,
  eventFiltersIntegration,
  functionToStringIntegration,
  getCurrentScope,
  globalHandlersIntegration,
  httpContextIntegration,
  linkedErrorsIntegration,
  makeFetchTransport,
  setCurrentClient,
} from '@sentry/browser';
import {
  type Breadcrumb,
  type ErrorEvent,
  type Integration,
  type TransactionEvent,
} from '@sentry/core';
import * as SentryVue from '@sentry/vue';
import type { App, Plugin } from 'vue';
import type { Router, RouteMeta as VueRouteMeta } from 'vue-router';
import {
  applyActorIdentity,
  resolveBootstrapActor,
  sanitizeEventUser,
  type IdentityScope,
} from './diagnostics/actorIdentity';
import {
  HTTP_BREADCRUMB_DATA_KEYS,
  NAVIGATION_BREADCRUMB_DATA_KEYS,
  applyFreeTextPolicy,
  httpBreadcrumbDurationFromHint,
  pickAllowedData,
} from './diagnostics/breadcrumbPolicy';
import { collectValuesToRedact, scrubUrlWithValues } from '@/utils/diagnostics/urlScrubbing';
// Re-export scrubbing utilities from dependency-free module for backward compatibility
export {
  EMAIL_PATTERN,
  SENSITIVE_PATH_PATTERN,
  VERIFIABLE_ID_PATTERN,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from '@/utils/diagnostics/scrubbers';

export const SENTRY_KEY = Symbol('sentry');

// Import functions for local use (patterns are re-exported above for external consumers)
import {
  scrubQueryStringValues,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from '@/utils/diagnostics/scrubbers';

/**
 * Two-layer URL scrubbing for a single URL string:
 *   1. Path-param VALUE scrubbing (governed by `sentryScrubParams`) — redacts
 *      the specific resolved param values passed in `sortedValues`.
 *   2. The always-on pattern safety-net (`scrubUrlWithPatterns`) — redacts
 *      emails, 62-char verifiable IDs and sensitive path segments by shape.
 *
 * Layer 2 runs even when `sortedValues` is empty, i.e. when a route opts out of
 * param scrubbing (`sentryScrubParams: false`) or simply has no path params.
 * The opt-out only governs which *param values* are scrubbed (layer 1); it must
 * never disable the PII/secret net, or an email carried in a query string
 * (?email=...) would reach Sentry unredacted. See src/utils/pii.ts and
 * src/router/README.md "Query-string policy".
 */
function scrubUrlValuesThenPatterns(url: string, sortedValues: string[]): string {
  const valueScrubbed = sortedValues.length > 0 ? scrubUrlWithValues(url, sortedValues) : url;
  return scrubUrlWithPatterns(valueScrubbed);
}

/**
 * Route-shaped input for `collectRouteParamValues`: anything carrying resolved
 * `meta` and `params` — the router's current route, a `router.resolve()`
 * result, etc.
 */
interface ResolvedRouteLike {
  meta: VueRouteMeta;
  params: Record<string, string | string[]>;
}

/**
 * Collects the route-param VALUES to redact for a resolved-route-like object,
 * honoring the `sentryScrubParams` opt-out. Single implementation shared by
 * the error handler (current route), the breadcrumb handler (route resolved
 * from the navigation path), and the transaction handler (route resolved from
 * the event's own URL).
 *
 * Layer-1 (param-value) scrubbing is opt-out-governed: `sentryScrubParams:
 * false` yields no values. The always-on pattern net inside
 * `scrubUrlValuesThenPatterns` runs regardless of the return value here.
 */
function collectRouteParamValues(route: ResolvedRouteLike): string[] {
  const sentryScrubParams = route.meta.sentryScrubParams as RouteMeta['sentryScrubParams'];
  if (sentryScrubParams === false) {
    return [];
  }
  const params = route.params;
  if (params && Object.keys(params).length > 0) {
    return collectValuesToRedact(params, sentryScrubParams);
  }
  return [];
}

/**
 * Collects the route-param VALUES to redact for the router's *current* route.
 * Appropriate for error events, which are captured synchronously while the
 * route that produced them is still current.
 */
function collectCurrentRouteValues(router: Router): string[] {
  const currentRoute = router.currentRoute.value;
  return collectRouteParamValues({
    meta: currentRoute.meta,
    params: currentRoute.params as Record<string, string | string[]>,
  });
}

/**
 * Resolves the route-param VALUES to redact from a path/URL string, or null if
 * the string cannot be resolved to a route.
 */
function resolveRouteValuesFromPath(router: Router, location: string): string[] | null {
  try {
    // router.resolve wants an in-app location, not a full URL. Synthetic base
    // so bare paths and absolute URLs both parse; the base is discarded.
    const parsed = new URL(location, 'http://_');
    const resolved = router.resolve(parsed.pathname + parsed.search + parsed.hash);
    return collectRouteParamValues(resolved as ResolvedRouteLike);
  } catch {
    return null;
  }
}

/**
 * Collects the route-param VALUES to redact for the route a *transaction*
 * event belongs to. Transactions (pageload/navigation) can still be in flight
 * when the user navigates away, so `router.currentRoute` may describe a
 * different route than the one the event's URLs point at — reading the live
 * route there would silently borrow the wrong page's params.
 */
function collectTransactionRouteValues(router: Router, event: TransactionEvent): string[] {
  // 1. Preferred: the transaction's OWN route, resolved from request.url. Carries
  //    the real param values, correct even after the user has navigated on.
  const url = event.request?.url;
  if (url) {
    const values = resolveRouteValuesFromPath(router, url);
    if (values) return values; // note: [] is a valid resolution (no/opted-out params)
  }

  // 2. No usable URL. The current route's params are this transaction's values
  //    ONLY if we have not navigated since it began. `event.transaction` is
  //    stamped at transaction start and names the transaction's own route
  //    (parameterized, e.g. `/secret/:secretKey`); compare it to the current
  //    route's parameterized path. On a mismatch the user navigated away — the
  //    current route's params belong to a DIFFERENT page, so applying them would
  //    miss this transaction's value AND redact unrelated strings. Return no
  //    values and let the always-on pattern/path nets be the floor.
  //
  //    Residual limitation: a short, meta-scrubbed param on a non-sensitive-path
  //    route, once its URL is gone and the user has navigated away, is
  //    unrecoverable at the value layer — only the nets apply.
  const current = router.currentRoute.value;
  const currentPath = current.matched?.at(-1)?.path ?? current.path;
  if (!event.transaction || event.transaction === currentPath) {
    return collectRouteParamValues({
      meta: current.meta,
      params: current.params as Record<string, string | string[]>,
    });
  }
  return [];
}

/** Scrubs any case variant of the Referer header value through the URL scrubber. */
function scrubRefererHeader(
  headers: Record<string, string> | undefined,
  sortedValues: string[]
): void {
  if (!headers) {
    return;
  }
  for (const name of Object.keys(headers)) {
    const value = headers[name];
    if (name.toLowerCase() === 'referer' && typeof value === 'string') {
      headers[name] = scrubUrlValuesThenPatterns(value, sortedValues);
    }
  }
}

/**
 * SINGLE shared scrub entrypoint for the fields common to error and
 * transaction events. Invoked from BOTH `createBeforeSendHandler` and
 * `createBeforeSendTransactionHandler` so a field can never be scrubbed in one
 * handler and silently forgotten in the other.
 *
 * Covers:
 *   - request.url — two-layer (param values + pattern net)
 *   - request.headers Referer — httpContextIntegration attaches
 *     document.referrer here; a referrer is a full URL and can carry secret
 *     identifiers/emails, so it goes through the same URL scrubber. Header name
 *     casing varies by transport (Referer / referer), so every case-insensitive
 *     match is scrubbed.
 *   - transaction — raw pageload names get the net. Parameterized route names
 *     (`/secret/:secretKey`) survive layer 2 because every path pattern
 *     requires a value-shaped segment where the placeholder sits:
 *     SENSITIVE_PATH_PATTERN needs `[a-zA-Z0-9]+` immediately after the slash
 *     and a leading `:` is neither, while the generated route patterns are all
 *     `/api/...` paths that a browser transaction name never takes. They are
 *     NOT unconditionally untouched, though: layer 1 redacts the current
 *     route's param VALUES by substring, so a value that happens to equal a
 *     literal segment of its own route (`/account/:section` visited with
 *     `section=account`) rewrites that segment. Cosmetic, and strictly on the
 *     safe side of the trade.
 *   - user — final-gate whitelist to `{ id, ip_address: null }`, where `id` is
 *     kept only when it matches ACTOR_REF_PATTERN (16 lowercase hex, the
 *     server's derivation shape) and the whole context is dropped otherwise.
 *     `applyActorIdentity` is the only sanctioned writer of user context, but
 *     `Sentry.setUser()` is a global API and integrations can write it too, so
 *     the outbound path re-asserts both the key set AND the value shape rather
 *     than trusting them. Checking the value is what makes this a filter and
 *     not a launderer: a keys-only gate would delete `email` while faithfully
 *     forwarding `setUser({ id: cust.email })`. SCOPE THE GUARANTEE EXACTLY: it
 *     covers the `user` CONTEXT, on every event, regardless of who populated
 *     the scope — no email, username, or SDK-attached IP survives there. It
 *     says nothing about other fields; an email interpolated into an exception
 *     message or a URL is the free-text scrubbers' job, above.
 *     See src/plugins/core/diagnostics/actorIdentity.ts.
 *
 * Event-kind-specific fields (error breadcrumbs, transaction spans) are handled
 * by the respective callers, not here.
 */
function scrubCommonEventFields(
  event: ErrorEvent | TransactionEvent,
  sortedValues: string[]
): void {
  sanitizeEventUser(event as { user?: Record<string, unknown> | null });

  if (event.request?.url) {
    event.request.url = scrubUrlValuesThenPatterns(event.request.url, sortedValues);
  }

  scrubRefererHeader(event.request?.headers, sortedValues);

  if (event.transaction) {
    event.transaction = scrubUrlValuesThenPatterns(event.transaction, sortedValues);
  }
}

/**
 * Scrubs and allowlists a `navigation` breadcrumb in place.
 *
 * Layer 1 (path-param VALUE scrubbing) is opt-out-governed and needs the route
 * resolved from the breadcrumb's OWN path — not the live current route, which
 * by the time a navigation breadcrumb is recorded may already be the
 * destination. Layer 2 (the pattern net inside `scrubUrlValuesThenPatterns`) is
 * unconditional and still runs when resolution fails or yields no values.
 *
 * After scrubbing, `data` is reduced to `{ from, to }` — Sentry's history
 * instrumentation emits nothing else, so anything else present came from an
 * unreviewed producer. See diagnostics/breadcrumbPolicy.ts.
 */
function scrubNavigationBreadcrumb(router: Router, breadcrumb: Breadcrumb): void {
  const scrubNavigationUrl = (path: string): string => {
    if (!path || typeof path !== 'string') {
      return path;
    }

    let sortedValues: string[] = [];
    try {
      const resolved = router.resolve(path);
      sortedValues = collectRouteParamValues(resolved as ResolvedRouteLike);
    } catch {
      // Resolution failed — fall through to the always-on pattern net below.
    }

    return scrubUrlValuesThenPatterns(path, sortedValues);
  };

  const data = breadcrumb.data;
  if (!data) {
    return;
  }
  if (data.to) {
    data.to = scrubNavigationUrl(data.to as string);
  }
  if (data.from) {
    data.from = scrubNavigationUrl(data.from as string);
  }
  breadcrumb.data = pickAllowedData(data, NAVIGATION_BREADCRUMB_DATA_KEYS);
}

/**
 * Creates a Sentry beforeBreadcrumb handler enforcing the METADATA-ONLY
 * breadcrumb policy.
 *
 * Two controls run here, and they cover DIFFERENT populations — read the split
 * literally, because it is the difference between what this handler enforces
 * and what it merely tidies:
 *
 * 1. **Value scrubbing — EVERY category.** The universal free-text pass in
 *    `applyFreeTextPolicy` (message scrubbing for every category,
 *    `data.arguments` dropped on console breadcrumbs), plus category-specific
 *    URL scrubbing for the two categories that carry URLs.
 * 2. **Structural allowlisting — ONLY `navigation`, `xhr` and `fetch`.** For
 *    those three, `data` is reduced to a fixed key set and anything outside it
 *    is dropped whether or not this codebase knows the key exists. Every other
 *    category (console, ui.click, ui.input, history, sentry.*) keeps its `data`
 *    bag structurally intact — see the "All other categories" note below for
 *    why, and src/plugins/core/diagnostics/breadcrumbPolicy.ts for the full
 *    retained/refused sets.
 *
 * The two controls are deliberately independent where both apply: scrubbing
 * catches sensitive VALUES in keys we expect, allowlisting catches entire KEYS
 * we did not.
 *
 * **Navigation breadcrumbs** (`category === 'navigation'`):
 * Uses router.resolve() to get route metadata and params for accurate scrubbing.
 * This ensures the correct route context is used, not the current route. `data`
 * is then reduced to `{ from, to }`.
 *
 * **HTTP breadcrumbs** (`category === 'xhr' || 'fetch'`):
 * Uses regex patterns since API URLs don't correspond to Vue routes.
 * Scrubs known sensitive paths (/secret/, /private/, /receipt/, /incoming/)
 * and 62-char verifiable IDs as a fallback. `data` is then reduced to the
 * metadata-only key set (url, method, status_code, duration, byte counts,
 * correlation ids) — which is what drops `request_body` / `response_body`,
 * `request.headers` and any other header or cookie key, and would drop any
 * future body/header capture the SDK might add.
 *
 * The two BYTE-COUNT keys (`request_body_size` / `response_body_size`) are
 * RETAINED, deliberately: a number of bytes is not content, and it is the one
 * signal that separates an EMPTY response from a TRUNCATED one from a
 * full-size-but-wrong-shape one. That policy, the full retained/refused sets,
 * and the per-key TYPE check that makes "a byte count is a number" enforced
 * rather than assumed all live in diagnostics/breadcrumbPolicy.ts — read it
 * there rather than restating it here.
 *
 * **All other categories** (console, ui.click, ui.input, history, sentry.*):
 * previously passed through untouched. They now get the free-text pass, so an
 * email or verifiable identifier interpolated into a console message or carried
 * in DOM element text is netted by shape.
 *
 * @param router - Vue Router instance for resolving navigation paths
 * @returns Sentry beforeBreadcrumb callback
 *
 * @internal Exported for testing
 */
function createBeforeBreadcrumbHandler(router: Router) {
  return (breadcrumb: Breadcrumb, hint?: unknown): Breadcrumb | null => {
    const category = breadcrumb.category;

    // Universal free-text policy first: it applies to every category, including
    // the two handled specially below, so it must not sit behind their returns.
    applyFreeTextPolicy(breadcrumb);

    // Handle navigation breadcrumbs using route resolution
    if (category === 'navigation' && breadcrumb.data) {
      scrubNavigationBreadcrumb(router, breadcrumb);
      return breadcrumb;
    }

    // Handle HTTP breadcrumbs using regex patterns.
    //
    // NOTE the guard is on the category alone, NOT on `data.url`. The earlier
    // `&& breadcrumb.data?.url` form meant a body-carrying breadcrumb with no
    // url skipped the handler entirely; the allowlist has to run for every
    // xhr/fetch breadcrumb, url or not.
    if (category === 'xhr' || category === 'fetch') {
      if (typeof breadcrumb.data?.url === 'string') {
        breadcrumb.data.url = scrubUrlWithPatterns(breadcrumb.data.url);
      }
      breadcrumb.data = pickAllowedData(breadcrumb.data, HTTP_BREADCRUMB_DATA_KEYS);

      // Timing lives in the HINT, not in `data` — @sentry/browser's fetch/xhr
      // instrumentation passes `{ startTimestamp, endTimestamp }` alongside the
      // breadcrumb and never writes `data.duration`. Folding it in here is what
      // makes the allowlist's `duration` entry real rather than aspirational.
      // Applied AFTER the allowlist so it can never be used to smuggle a key
      // past it, and only when a producer has not already supplied one.
      const duration = httpBreadcrumbDurationFromHint(hint);
      if (duration !== undefined) {
        if (!breadcrumb.data) {
          breadcrumb.data = { duration };
        } else if (breadcrumb.data.duration === undefined) {
          breadcrumb.data.duration = duration;
        }
      }
      return breadcrumb;
    }

    // Every other category: free-text policy already applied above. `data` is
    // left structurally intact — these categories have no known producer of
    // request/response content, and blanket-dropping their data would gut
    // ui.click / history diagnostics for no privacy gain.
    return breadcrumb;
  };
}

/**
 * Scrubs sensitive data from exception messages and standalone messages in an event.
 * Applies regex-based scrubbing to catch interpolated secrets/emails in error strings.
 *
 * @param event - The Sentry error event to scrub
 * @returns The modified event (mutated in place)
 */
function scrubEventMessages(event: ErrorEvent): ErrorEvent {
  if (event.exception?.values) {
    event.exception.values = event.exception.values.map((exc) => {
      if (exc.value) {
        exc.value = scrubSensitiveStrings(exc.value);
      }
      return exc;
    });
  }

  if (event.message) {
    event.message = scrubSensitiveStrings(event.message);
  }

  return event;
}

/**
 * Creates a Sentry beforeSend handler that scrubs sensitive data from events.
 * Handles both URL scrubbing (route-param based) and message scrubbing (regex-based).
 *
 * @internal Exported for testing
 */
function createBeforeSendHandler(router: Router) {
  return (event: ErrorEvent): ErrorEvent | null | Promise<ErrorEvent | null> => {
    if ('secret' in event && event.secret) {
      delete event.secret;
    }

    // Scrub exception messages and standalone messages (regex-based)
    scrubEventMessages(event);

    // Collect route-param values for the current route (opt-out-governed).
    const sortedValues = collectCurrentRouteValues(router);

    // Scrub the fields shared with transaction events (request.url, Referer
    // header, transaction) through the single shared entrypoint.
    scrubCommonEventFields(event, sortedValues);

    // Second breadcrumb pass. `beforeBreadcrumb` already applied the
    // metadata-only policy at CAPTURE time; this pass re-runs BOTH controls at
    // SEND time:
    //
    //   1. the free-text policy and the URL scrubbers, now with the route-param
    //      VALUES in hand (layer 1), which the capture-time handler does not
    //      always have — a breadcrumb recorded before the router resolved gets
    //      its param values only here; and
    //   2. the structural allowlist, per category.
    //
    // (2) is what makes "covered whether or not this codebase knows it exists"
    // true of the breadcrumbs actually on the wire. A breadcrumb that reaches
    // `event.breadcrumbs` WITHOUT passing beforeBreadcrumb — attached by the SDK
    // after it ran, or by a future integration that bypasses it — otherwise
    // keeps every key in `data`, including the `request_body` / `response_body`
    // / `request.headers` the capture-time allowlist exists to refuse. Low
    // reachability today (scope.addBreadcrumb routes through the client's
    // beforeBreadcrumb), which is exactly why it must not depend on that routing
    // staying true.
    //
    // Cost and idempotency: `pickAllowedData` is a subset selection over a fixed
    // ≤9-key list with a `typeof` per key, and it is IDEMPOTENT — a breadcrumb
    // that already passed the capture-time allowlist holds only allowlisted,
    // correctly typed keys, so this pass returns an equal object and changes
    // nothing (verified against the capture-time output, including the
    // `duration` folded in from the hint AFTER the first allowlist ran).
    // Categories with no allowlist keep their `data` here for the same reason
    // they keep it at capture time.
    if (event.breadcrumbs) {
      event.breadcrumbs = event.breadcrumbs.map((breadcrumb: Breadcrumb) => {
        applyFreeTextPolicy(breadcrumb);
        if (breadcrumb.data) {
          if (breadcrumb.data.url) {
            breadcrumb.data.url = scrubUrlValuesThenPatterns(
              breadcrumb.data.url as string,
              sortedValues
            );
          }
          if (breadcrumb.data.to) {
            breadcrumb.data.to = scrubUrlValuesThenPatterns(
              breadcrumb.data.to as string,
              sortedValues
            );
          }
          if (breadcrumb.data.from) {
            breadcrumb.data.from = scrubUrlValuesThenPatterns(
              breadcrumb.data.from as string,
              sortedValues
            );
          }
          // Structural allowlist, re-applied. Same key sets and same order
          // (scrub, then reduce) as the capture-time handler.
          if (breadcrumb.category === 'navigation') {
            breadcrumb.data = pickAllowedData(breadcrumb.data, NAVIGATION_BREADCRUMB_DATA_KEYS);
          } else if (breadcrumb.category === 'xhr' || breadcrumb.category === 'fetch') {
            breadcrumb.data = pickAllowedData(breadcrumb.data, HTTP_BREADCRUMB_DATA_KEYS);
          }
        }
        return breadcrumb;
      });
    }

    return event;
  };
}

/**
 * Creates a Sentry beforeSendTransaction handler that scrubs sensitive URLs
 * from performance (transaction) events.
 *
 * `beforeSend` only runs for error events — transaction events bypass it
 * entirely. With tracing enabled (tracesSampleRate > 0), pageload/navigation
 * transactions carry the raw URL in `transaction`, `request.url`, and in
 * fetch/xhr span descriptions. The router instrumentation usually
 * parameterizes the transaction name, but the initial pageload name and span
 * URLs are raw, so everything gets the pattern net here.
 *
 * Runs the SAME shared entrypoint as `createBeforeSendHandler`, including the
 * route-param VALUE layer (D2), so a value scrubbed on error events is scrubbed
 * on transaction events too. Route context is resolved from the transaction's
 * own `request.url` (see `collectTransactionRouteValues`) — NOT the live
 * current route, which may already describe a later navigation by the time an
 * in-flight transaction is finalized.
 *
 * @internal Tested via the options captured by the BrowserClient mock,
 * same as createBeforeSendHandler.
 */
function createBeforeSendTransactionHandler(router: Router) {
  return (event: TransactionEvent): TransactionEvent | null => {
    const sortedValues = collectTransactionRouteValues(router, event);

    // Shared entrypoint: request.url, Referer header, transaction name.
    scrubCommonEventFields(event, sortedValues);

    if (!event.spans) {
      return event;
    }
    for (const span of event.spans) {
      // Descriptions are free text ("GET /api/v2/secret/<id>"), not URLs —
      // scrubUrlWithPatterns would route them through the URL parser and
      // mangle the method prefix, so use the string scrubber.
      if (span.description) {
        span.description = scrubSensitiveStrings(span.description);
      }
      if (!span.data) {
        continue;
      }
      for (const key of ['url', 'http.url', 'url.full'] as const) {
        const value = span.data[key];
        if (typeof value === 'string') {
          span.data[key] = scrubUrlWithPatterns(value);
        }
      }
      // http.query is stored as `parsedUrl.search`, which INCLUDES the
      // leading `?` (@sentry/core fetch instrumentation) — scrub it as a
      // query string (sensitive param values by name, then the ID/email
      // nets); the scrubber handles the leading `?` itself.
      const query = span.data['http.query'];
      if (typeof query === 'string') {
        span.data['http.query'] = scrubQueryStringValues(query);
      }
    }

    return event;
  };
}

/**
 * Applies the deployment tags (service / site_host / jurisdiction) to every
 * given scope. Deployment tags must live on BOTH scopes:
 *   - the isolated `Scope`, so manual captures (diagnostics.service) carry
 *     them, and
 *   - the CURRENT scope, because `setCurrentClient` routes integration-
 *     captured events (unhandled rejections, browserApiErrors async
 *     callbacks, browserTracing transactions) through the current scope —
 *     tags set only on the detached isolated scope never reach those events.
 *
 * @see https://github.com/onetimesecret/onetimesecret/issues/2964 (service)
 * @see lib/onetime/initializers/setup_diagnostics.rb (site_host mirrors the
 *   backend so multi-region / custom-domain deployments are distinguishable)
 */
function applyDeploymentTags(scopes: Array<Pick<Scope, 'setTag'>>, host: string): void {
  // Jurisdiction comes from the bootstrap value directly since Pinia is not
  // yet installed when createDiagnostics() is called.
  const regions = getBootstrapValue('regions');
  const jurisdictionId =
    typeof regions?.current_jurisdiction === 'string'
      ? regions.current_jurisdiction.toLowerCase()
      : null;

  for (const scope of scopes) {
    scope.setTag('service', 'web');
    if (host) {
      scope.setTag('site_host', host);
    }
    if (jurisdictionId) {
      scope.setTag('jurisdiction', jurisdictionId);
    }
  }
}

interface EnableDiagnosticsOptions {
  // Display domain. This is the domain the user is interacting with, not
  // the Sentry domain. Same meaning as `display_domain`.
  host: string;
  // Sentry configuration from backend (caller must ensure non-null)
  config: NonNullable<DiagnosticsConfig>;
  // Vue Router instance for route tracking
  router: Router;
}

export interface SentryInstance {
  client: BrowserClient;
  scope: Scope;
}

/**
 * Creates a Vue plugin instance that initializes Sentry error tracking.
 * Follows factory pattern like createPinia().
 *
 * @plugin
 *
 * @param {EnableDiagnosticsOptions} options
 * @returns {Plugin} Vue plugin instance
 *
 * @example
 * ```ts
 * const diagnostics = createDiagnostics({
 *   host: displayDomain,
 *   config: window.diagnostics,
 *   router: router
 * });
 * app.use(diagnostics);
 * ```
 *
 *
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/options/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/best-practices/sentry-testkit/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/sourcemaps/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/integrations/browserapierrors/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/features/
 */
export function createDiagnostics(options: EnableDiagnosticsOptions): Plugin {
  const { host, config, router } = options;

  // @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/tree-shaking/
  const integrations: Integration[] = [
    breadcrumbsIntegration(),
    globalHandlersIntegration(),
    linkedErrorsIntegration(),
    dedupeIntegration(),
    // Attaches request.url (location.href), referrer, and user-agent to every
    // event. Without this, events arrive with an empty `url` field. The URL is
    // scrubbed on the way out — by `scrubCommonEventFields`, which both
    // `beforeSend` and `beforeSendTransaction` call, so errors and transactions
    // get the same treatment: layer 1 redacts the route's own resolved param
    // VALUES, layer 2 redacts by SHAPE (sensitive path prefixes, emails,
    // 62/31-char verifiable ids, prefixed object ids, UUIDs, IP literals, and
    // sensitive query-param values by name). Between them that covers every
    // identifier shape this app puts in a URL today. It is not a proof: a
    // future identifier of an unrecognised shape, sitting on a route that opted
    // out of param scrubbing, would survive both layers. Adding a shape to
    // src/utils/diagnostics/scrubbers.ts is how that gets closed.
    //
    // PRIVACY AUDIT (requirement 3): this integration attaches exactly three
    // things — `request.url`, `request.headers.Referer`, and
    // `request.headers['User-Agent']`. Read out of the installed SDK, not
    // assumed: `getHttpRequestData()` in @sentry/browser's helpers builds
    // `{ url, headers: { Referer?, 'User-Agent'? } }` and nothing else. It does
    // NOT attach an IP address, an email, a cookie, or any other header; there
    // is no client-side source for the reporter's IP in a browser at all. The
    // Referer is a full URL and is scrubbed in `scrubCommonEventFields`. An SDK
    // upgrade that widens that function widens this comment's claim with it, so
    // re-read it when the dependency moves.
    //
    // The remaining IP exposure is SERVER-side: Sentry's ingest sees the TCP
    // source address of the transport request and substitutes it for
    // `user.ip_address` when that field is `{{auto}}` or when
    // `sendDefaultPii` is true. Both are closed here — `sendDefaultPii: false`
    // below, and actor identity pins an explicit `ip_address: null` that
    // `sanitizeEventUser` re-asserts on every outbound event.
    //
    // The transport (`makeFetchTransport`, set below) is the stock fetch
    // transport: it POSTs the serialized envelope and adds no identity headers
    // of its own.
    httpContextIntegration(),
    // Drops known-noise events (browser extension errors, old-browser
    // garbage, matching denyUrls/ignoreErrors) before they hit the server.
    // Renamed from inboundFiltersIntegration, deprecated in v10.
    eventFiltersIntegration(),
    // Wraps timer/event-listener/XHR callbacks so async errors carry full
    // synthetic stack traces instead of terminating at the browser API boundary.
    browserApiErrorsIntegration(),
    // Preserves original function identity in stack traces for functions
    // wrapped by browserApiErrors.
    functionToStringIntegration(),
    SentryVue.browserTracingIntegration({ router }),

    /**
     * Sentry Replay is disabled. There is a conflict with strict CSP headers
     * and defining workers with a blob. The solution is to remove the worker
     * code during the build process and to serve it from a static file. The
     * worker compresses payloads for session replay which would otherwise be
     * large and slow to upload.
     *
     * @see https://github.com/getsentry/sentry-javascript/pull/9409
     * @see (original thread) https://github.com/getsentry/sentry-javascript/issues/6739
     *
     */
    // SentryVue.replayIntegration(),
  ];

  // All options you normally pass to Sentry.init. The values
  // here are the defaults if not provided in options.
  const sentryOptions = {
    // debug: Use local DEBUG flag (dev convenience override)
    debug: DEBUG,
    // sampleRate: Use backend config value, default to 1.0 to capture all errors.
    // Errors are low-volume and represent actual problems worth tracking.
    // This differs from tracesSampleRate which controls performance trace sampling.
    sampleRate: config.sentry.sampleRate ?? 1.0,
    transport: makeFetchTransport,
    stackParser: defaultStackParser,
    // tracesSampleRate: Keep low default since YAML doesn't define it and traces are high-volume
    tracesSampleRate: config.sentry.tracesSampleRate ?? 0.01,
    /** Session Replay is disabled. See note above. */
    // replaysSessionSampleRate: 0.1, // Capture 10% of the sessions
    // replaysOnErrorSampleRate: 1.0, // Capture 100% of the errors

    ...config.sentry, // includes dsn, environment, etc.

    // ═════════════════════════════════════════════════════════════════════════
    // EVERYTHING BELOW THIS LINE IS PINNED AFTER THE SPREAD, ON PURPOSE.
    // ═════════════════════════════════════════════════════════════════════════
    //
    // `config.sentry` is a BACKEND-AUTHORED object arriving in the bootstrap
    // payload. `sendDefaultPii`, `dist` and `normalizeDepth` were already
    // pinned below it, each with the same one-line rationale: the frontend, not
    // the backend payload, is the authority on this field.
    //
    // The three handlers and two option lists that follow are the privacy
    // boundary ITSELF — `beforeSend`, `beforeSendTransaction` and
    // `beforeBreadcrumb` are the functions that scrub every event, transaction
    // and breadcrumb this client emits, `integrations` is the closed list that
    // keeps Replay and network-detail capture off, and
    // `tracePropagationTargets` decides who receives our trace headers. They
    // sat ABOVE the spread, which made them the one part of this config a
    // backend-authored key could replace. That is the inverse of the intended
    // ordering: if any field deserves the pin, these do.
    //
    // `sentryConfigSchema` (src/schemas/contracts/bootstrap.ts) is a plain
    // `z.object`, so an unknown `beforeSend` key is stripped from the payload
    // TODAY and none of this is reachable. That is exactly the argument the
    // `sendDefaultPii` note makes about itself and then declines to rely on: it
    // is one `z.looseObject`, or one added field, away from ceasing to be true,
    // and nothing announces the change when it does. Applying the discipline
    // consistently costs one reordering; discovering the gap costs an
    // unscrubbed event stream.

    // Scrub sensitive route params from URLs in error events
    beforeSend: createBeforeSendHandler(router),

    // Scrub URLs from performance events (beforeSend does not run for these)
    beforeSendTransaction: createBeforeSendTransactionHandler(router),

    // Scrub sensitive URLs from breadcrumbs at capture time
    beforeBreadcrumb: createBeforeBreadcrumbHandler(router),

    // Only the integrations listed here will be used
    integrations,

    /**
     * NARROW trace-header allowlist.
     *
     * `sentry-trace` and `baggage` are outbound headers, and every entry here
     * is a decision to hand their bearer our trace context. The rule, stated as
     * the code actually implements it:
     *
     *   RELATIVE PATHS, `localhost`, AND THE DISPLAY HOST INCLUDING ANY
     *   SUBDOMAIN OF IT. Nothing else. Never `true` (which would propagate to
     *   every host the app ever calls), and never an unanchored suffix match.
     *
     * Entry 3 IS broader than same-origin, and that is deliberate rather than
     * accidental: a deployment's regional instances are subdomains of the
     * display host (`eu.example.com`, `us.example.com`), so a strict
     * same-origin rule would silently break trace continuation the moment a
     * regional host is introduced, in a way nothing would flag. The width is
     * bounded by the anchoring — `^https?://` at the front and `(:\d+)?(/|$)`
     * at the back — so the host must END the domain portion. That is what
     * refuses `example.com.attacker.io`, which an unanchored suffix rule would
     * accept. What entry 3 does admit is any host under a domain the operator
     * already controls, which is the correct trust boundary for a trace header.
     *
     * 1. `/^\/(?!\/)/` — relative paths. This is the entry that actually does
     *    the work, because that is the shape of every real request today:
     *    `createApi()` (src/api/index.ts) only sets `baseURL` when a `domain`
     *    is passed, and no production call site passes one. The negative
     *    lookahead is load-bearing: a bare `/^\//` also matches the
     *    PROTOCOL-RELATIVE form `//third-party.example/x`, which is
     *    cross-origin. Excluding a second leading slash keeps the rule to
     *    genuinely same-origin paths.
     *
     * 2. `^https?://localhost(:port)?(/|$)` — absolute localhost URLs in dev.
     *    This replaces the previous `/^localhost(:\d+)?$/`, which was DEAD:
     *    Sentry matches against the fully-resolved absolute URL
     *    (`http://localhost:5173/api/...`), and `^localhost` can never match a
     *    string starting with `http`.
     *
     * 3. The `host` regex — absolute URLs on the display host and its
     *    subdomains, anchored as described above. Omitted entirely when no
     *    host is known, so an unknown host allows nothing rather than
     *    everything.
     *
     * Backend continuation: inbound `sentry-trace` / `baggage` are consumed by
     * `Sentry::Rack::CaptureExceptions`, mounted in
     * lib/onetime/application/middleware_stack.rb. No CORS layer exists and no
     * cross-origin call is made, so no preflight allow-headers entry is needed.
     */
    tracePropagationTargets: [
      /^\/(?!\/)/,
      /^https?:\/\/localhost(:\d+)?(\/|$)/i,
      // Add host domain regex only if host is provided.
      // Properly anchored: requires host to be at the end of the domain portion,
      // either at end of string or followed by / or :port
      ...(host
        ? [new RegExp(`^https?://([a-z0-9-]+\\.)*${host.replaceAll('.', '\\.')}(:\\d+)?(/|$)`, 'i')]
        : []),
    ],

    /**
     * PII collection is off, and it is pinned AFTER the `config.sentry` spread
     * on purpose.
     *
     * `false` is the SDK default, so this looks redundant — it is not. The
     * spread above merges a backend-controlled object into these options. The
     * diagnostics contract does not declare `sendDefaultPii` today, but the
     * contract is a server-side artifact and this is a one-line change away
     * from turning on IP-address and cookie collection for every browser
     * session without any frontend review. Pinning it after the spread makes
     * the frontend the authority on that switch.
     *
     * With this false, @sentry/browser does not attach `user.ip_address`,
     * cookies, or request headers beyond what `httpContextIntegration`
     * explicitly sets (url, referrer, user-agent — the referrer is scrubbed in
     * `scrubCommonEventFields`). Actor identity additionally pins
     * `ip_address: null` so Sentry's server-side inference has nothing to
     * substitute either way — see diagnostics/actorIdentity.ts.
     */
    sendDefaultPii: false,

    // Build-time release takes precedence over backend config.
    // This ensures frontend errors match the sourcemaps uploaded during this build,
    // which is critical for CDN caching and rolling deploys where the backend
    // might be running a newer release than the cached frontend bundle.
    release: __SENTRY_RELEASE__,

    /**
     * `dist` is a JOIN KEY, and it must be a LITERAL that matches CI exactly.
     *
     * Sentry resolves an artifact bundle for an event only when RELEASE AND
     * DIST both match. Sampled events on release b7aaea0 carried `dist: null`
     * while .github/workflows/build-and-publish-oci-images.yml uploaded with
     * `--dist=frontend`, so even a fully successful upload could never
     * symbolicate a single frame: two halves of one key, disagreeing silently.
     *
     * ┌─────────────────────────────────────────────────────────────────────┐
     * │ THE AGREED VALUE IS THE STRING LITERAL `frontend`, IN BOTH PLACES:  │
     * │   • here, as `dist: 'frontend'` in Sentry.init options              │
     * │   • CI, as `SENTRY_DIST: frontend` on the preflight and upload steps │
     * └─────────────────────────────────────────────────────────────────────┘
     *
     * THIS BRANCH SHIPS ONLY THE HALF ABOVE. CI's half — and the separate
     * reason the upload has always shipped zero files — land in
     * `fix/sentry-sourcemap-delivery`. Until that merges, this literal has no
     * counterpart and no frame symbolicates; neither ordering makes anything
     * worse, because dist-less events plus empty bundles is the state we are
     * already in. Both are required before symbolication works at all.
     *
     * Why a hardcoded literal rather than a build-time define or the backend
     * config: this value's only job is to be IDENTICAL to a string in a YAML
     * file. A define adds a second place it can be set and a build mode where
     * it silently becomes `undefined`; the backend config spread makes it
     * settable at runtime by a process that has never seen the upload command.
     * A literal is also the one form that CI's preflight check can read
     * directly out of this file and compare against `SENTRY_DIST`, which is
     * what turns a future drift into a CI warning instead of another year of
     * unsymbolicated stack traces.
     *
     * Pinned AFTER the `...config.sentry` spread for the same reason
     * `sendDefaultPii` is: the frontend, not the backend payload, is the
     * authority on this field.
     *
     * The alternative (no dist on either side) also works. It is NOT chosen
     * because dist-less is the state we are in today, it is indistinguishable
     * from "someone forgot", and it gives up the ability to ship two bundles
     * under one release. If it is ever revisited, both halves must drop it in
     * the same change.
     */
    dist: 'frontend',

    /**
     * `normalizeDepth` is PINNED, after the spread, for the same reason `dist`
     * and `sendDefaultPii` are — and here the thing being protected is the
     * diagnostic payload this whole boundary exists to deliver.
     *
     * Sentry normalizes `event.extra` before transport: primitives survive at
     * any depth, but a still-nested object at the depth limit is replaced by
     * the literal string `[Object]`. The schema-issue projection ships
     *
     *     extra = { issues: [ { path, code, expected, received } ] }
     *
     * whose containers sit at depths 1 and 2 with primitive leaves at 3.
     * MEASURED: `normalize(extra, 3)` preserves every projected row;
     * `normalize(extra, 2)` collapses `issues` to `["[Object]"]` — the entire
     * diagnostic payload, gone, with the event still delivered and still
     * looking healthy. There is ZERO margin, and the failure is silent.
     *
     * 3 is also the SDK default, so this pin changes nothing today. That is
     * the point: it removes the one path by which a backend-authored
     * `diagnostics.sentry` block could lower it. (`sentryConfigSchema` is
     * non-strict, so an unknown `normalizeDepth` key is stripped from the
     * bootstrap payload today — a fact that is one `z.looseObject`/one added
     * field away from ceasing to be true, and nothing announces the change
     * when it does.)
     *
     * NOT raised above 3 deliberately: a deeper budget would ship more of any
     * hand-assembled `captureException` context verbatim, widening the leak
     * surface to buy margin the projection does not need. The projection is
     * flat BY CONTRACT (see schemaIssueProjection.ts); if a row ever needs to
     * nest, flatten the row rather than raise this number.
     */
    normalizeDepth: 3,
  };

  // Guard behind DEBUG: sentryOptions includes the DSN and must not be logged
  // in production.
  if (DEBUG) {
    console.debug('[EnableDiagnostics] sentryOptions:', sentryOptions);
  }

  const client = new BrowserClient(sentryOptions);
  const scope = new Scope();
  scope.setClient(client);

  // Bind this client to the global current scope as well.
  //
  // This app uses an isolated Scope (above) for manual captures and tags, but
  // the integrations resolve their client via `getClient()` off the *current*
  // scope — not our isolated one. Without this binding:
  //   - browserApiErrorsIntegration cannot report the async-callback errors it
  //     wraps (timers, event listeners, XHR) — they are silently dropped.
  //   - browserTracingIntegration never records transactions, so
  //     beforeSendTransaction (and its scrubbing) never runs.
  // `setCurrentClient` points the current scope at the same client, so both
  // integrations resolve a real client and every event still passes through
  // this client's beforeSend/beforeSendTransaction scrubbers. Called before
  // client.init() to mirror Sentry's own initAndBind ordering.
  setCurrentClient(client);

  // Deployment tags on both the isolated scope (manual captures) and the
  // current scope (integration-captured events). See applyDeploymentTags.
  applyDeploymentTags([scope, getCurrentScope()], host);

  // Actor identity from the server-provided `diagnostics_actor` bootstrap block, on
  // the same two scopes and for the same reason.
  //
  // BOOT ORDERING: this runs inside createDiagnostics(), which appInitializer
  // calls AFTER consumeBootstrapData() and BEFORE app.use(pinia). The bootstrap
  // snapshot is therefore already populated and readable via
  // getBootstrapValue(), while the Pinia store is not yet constructed — hence
  // the service read rather than useBootstrapStore(). Sentry init is NOT moved
  // to accommodate identity.
  //
  // If the block is absent (anonymous session, error-page render with no
  // serializers, or an older backend), this is a no-op setUser(null) and the
  // session runs unidentified. Identity then arrives lazily through
  // bootstrapStore.update() -> setDiagnosticsActor() on the first
  // /bootstrap/me refresh or on login, without re-initializing Sentry.
  applyActorIdentity([scope, getCurrentScope()] as IdentityScope[], resolveBootstrapActor());

  // Set the event `transaction` field from the matched route record's
  // parameterized path (e.g. /secret/:secretKey), never the resolved URL.
  // Inherently free of secret identifiers, so nothing to scrub.
  //
  // Why here and not solely via browserTracingIntegration: manual captures go
  // through the isolated Scope above. The router instrumentation names
  // transactions on the *current* scope, which the isolated scope does not
  // share, so error events captured through the isolated scope would otherwise
  // have an empty `transaction`. (setCurrentClient binds the client so the
  // integrations run, but it does not merge the two scopes' transaction name.)
  // afterEach fires on the initial navigation as well, so pageload errors are
  // covered once routing resolves.
  // afterEach returns an unregister fn; capture it so repeated mount/unmount
  // (tests, micro-frontends) don't accumulate handlers. Unbound on unmount.
  const unregisterAfterEach = router.afterEach((to) => {
    const parameterized = to.matched.at(-1)?.path ?? to.path;
    scope.setTransactionName(parameterized);
  });

  // Initialize the Sentry client. This is equivalent to calling
  // Sentry.init() with the options provided above.
  client.init(); // after setting the client on the scope

  return {
    install(app: App) {
      // Initialize module-level diagnostics service for use outside Vue context
      // (e.g., globalErrorBoundary, schemaValidation)
      initDiagnostics(client, scope);

      // Provide Sentry instance using symbol key (for components using inject)
      app.provide(SENTRY_KEY, { client, scope });

      // Auto-cleanup on unmount. Otherwise some events might be
      // lost if the application shuts down unexpectedly.
      app.unmount = ((original) =>
        function (this: App) {
          unregisterAfterEach();
          client.close(2000).then(() => {
            original.call(this);
          });
        })(app.unmount);
    },
  };
}
