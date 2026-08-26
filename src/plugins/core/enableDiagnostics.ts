// src/plugins/core/enableDiagnostics.ts

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
  type EventHint,
  type Integration,
  type TransactionEvent,
} from '@sentry/core';
import * as SentryVue from '@sentry/vue';
import type { App, Plugin } from 'vue';
import type { Router, RouteMeta as VueRouteMeta } from 'vue-router';
import {
  applyActorContext,
  resolveDiagnosticsRef,
  sanitizeEventUser,
  type ActorContextScope,
} from './diagnostics/actorContext';
import { isExpectedTransportOutcome } from './diagnostics/expectedOutcomes';
import { applyGroupingRules } from './diagnostics/grouping';
import { collectValuesToRedact, scrubUrlWithValues } from './diagnostics/urlScrubbing';
// Re-export scrubbing utilities from dependency-free module for backward compatibility
export {
  EMAIL_PATTERN,
  SENSITIVE_PATH_PATTERN,
  VERIFIABLE_ID_PATTERN,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from './diagnostics/scrubbers';

export const SENTRY_KEY = Symbol('sentry');

/**
 * Message fingerprints of errors thrown by code that is not ours: browser
 * extensions, in-app webviews, and email-client link scanners. Secret links
 * are opened from email and chat clients, so this traffic share is unusually
 * high here (#4287). Consumed by eventFiltersIntegration via `ignoreErrors`
 * (matched as substring for strings, test for regexes, against the exception
 * message). Sentry's own default ignore list stays active alongside these.
 *
 * Revisit quarterly — the list will need additions as clients change.
 *
 * @internal Exported for testing
 */
export const THIRD_PARTY_IGNORE_ERRORS: (string | RegExp)[] = [
  // Firefox iOS reader-mode script injected at document scope
  /__firefox__/,
  // Microsoft Outlook SafeLinks scanning webview; the Id varies per event
  /Object Not Found Matching Id:\d+/,
  // Android WebView torn down mid-postMessage (Instagram/Meta in-app browser)
  'Java object is gone',
  // Zalo in-app browser injection ("zaloJSV2 is not defined" and
  // "Can't find variable: zaloJSV2")
  'zaloJSV2',
  // iOS webview whose host app never answered the bridge call (DuckDuckGo etc.)
  'WKWebView API client did not respond to this postMessage',
  // Chrome extension messaging its unloaded background counterpart
  'Could not establish connection. Receiving end does not exist',
  // Extensions redefining built-ins (e.g. Symbol.hasInstance); wording varies
  // by browser, so match the invariant middle
  /redefine non-configurable property/,
];

/**
 * Frame URLs of third-party code, matched against the topmost stack frame.
 * Consumed by eventFiltersIntegration via `denyUrls`.
 *
 * @internal Exported for testing
 */
export const THIRD_PARTY_DENY_URLS: RegExp[] = [
  /^chrome-extension:\/\//,
  /^moz-extension:\/\//,
  /^safari-(web-)?extension:\/\//,
  // Safari masks extension-injected frame URLs behind this scheme
  /^webkit-masked-url:\/\//,
  // Meta in-app browser performance instrumentation
  /^iabjs:\/\//,
];

/**
 * Only report errors whose topmost frame is our own bundle. Every first-party
 * script is served under /dist/ (production: /dist/assets/*.js via the Vite
 * manifest, dev: /dist/main.ts — see apps/web/core/views/helpers/
 * vite_manifest.rb), on canonical and custom domains alike, so this is a
 * path match rather than an origin match.
 *
 * Injected webview/extension code frequently executes at document scope, so
 * its frames are attributed to the page URL itself (observed: Firefox iOS
 * reader mode frames at /secret/<key>). Those never match /dist/ and get
 * dropped. Trade-off, accepted in #4287: errors from the inline theme
 * bootstrap script in index.rue are attributed to the page URL too and would
 * be dropped — that script is small and stable. Events with no frame URL at
 * all (e.g. many unhandled rejections) are NOT dropped by allowUrls.
 *
 * @internal Exported for testing
 */
export const FIRST_PARTY_ALLOW_URLS: RegExp[] = [/\/dist\//];

// Import functions for local use (patterns are re-exported above for external consumers)
import {
  scrubQueryStringValues,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from './diagnostics/scrubbers';

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
 *   - transaction — parameterized route names (`/secret/:secretKey`) pass
 *     through untouched; raw pageload names get the net.
 *   - user — final-gate whitelist to `{ id, ip_address: null }`, where `id` is
 *     kept only when it matches DIAGNOSTICS_REF_PATTERN (16 lowercase hex, the
 *     server's derivation shape) and the whole context is dropped otherwise.
 *     `applyActorContext` is the only sanctioned writer of user context, but
 *     `Sentry.setUser()` is a global API and integrations can write it too, so
 *     the outbound path re-asserts both the key set AND the value shape rather
 *     than trusting them. Checking the value is what makes this a filter and
 *     not a launderer: a keys-only gate would delete `email` while faithfully
 *     forwarding `setUser({ id: cust.email })`. The guarantee covers the
 *     `user` CONTEXT only; an email interpolated into an exception message or
 *     a URL is the free-text scrubbers' job.
 *     See src/plugins/core/diagnostics/actorContext.ts.
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
 * Creates a Sentry beforeBreadcrumb handler that scrubs sensitive URLs at capture time.
 *
 * This handler uses a hybrid approach based on breadcrumb category:
 *
 * **Navigation breadcrumbs** (`category === 'navigation'`):
 * Uses router.resolve() to get route metadata and params for accurate scrubbing.
 * This ensures the correct route context is used, not the current route.
 *
 * **HTTP breadcrumbs** (`category === 'xhr' || 'fetch'`):
 * Uses regex patterns since API URLs don't correspond to Vue routes.
 * Scrubs known sensitive paths (/secret/, /private/, /receipt/, /incoming/)
 * and 62-char verifiable IDs as a fallback.
 *
 * @param router - Vue Router instance for resolving navigation paths
 * @returns Sentry beforeBreadcrumb callback
 *
 * @internal Exported for testing
 */
function createBeforeBreadcrumbHandler(router: Router) {
  return (breadcrumb: Breadcrumb): Breadcrumb | null => {
    const category = breadcrumb.category;

    // Handle navigation breadcrumbs using route resolution
    if (category === 'navigation' && breadcrumb.data) {
      const scrubNavigationUrl = (path: string): string => {
        if (!path || typeof path !== 'string') {
          return path;
        }

        // Layer 1 (path-param VALUE scrubbing) is opt-out-governed; layer 2 (the
        // pattern net inside scrubUrlValuesThenPatterns) is not. Collect the
        // param values only when the route neither opts out nor lacks params;
        // otherwise fall through with no values and let the net still run.
        let sortedValues: string[] = [];
        try {
          const resolved = router.resolve(path);
          sortedValues = collectRouteParamValues(resolved as ResolvedRouteLike);
        } catch {
          // Resolution failed — fall through to the always-on pattern net below.
        }

        return scrubUrlValuesThenPatterns(path, sortedValues);
      };

      if (breadcrumb.data.to) {
        breadcrumb.data.to = scrubNavigationUrl(breadcrumb.data.to as string);
      }
      if (breadcrumb.data.from) {
        breadcrumb.data.from = scrubNavigationUrl(breadcrumb.data.from as string);
      }

      return breadcrumb;
    }

    // Handle HTTP breadcrumbs using regex patterns
    if ((category === 'xhr' || category === 'fetch') && breadcrumb.data?.url) {
      breadcrumb.data.url = scrubUrlWithPatterns(breadcrumb.data.url as string);
      return breadcrumb;
    }

    // Pass through all other breadcrumbs unchanged
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
 * Scrubs stack-frame locations through the URL pattern net.
 *
 * Code injected by extensions/webviews at document scope gets its frames
 * attributed to the page URL itself — which on a secret link IS the secret
 * path. Observed live (FRONTEND-155/154/184): events arrived with
 * `request.url` correctly `[REDACTED]` while the frame filename carried the
 * raw `/secret/<62-char-key>` verbatim. Our own bundle frames
 * (/dist/assets/*.js) contain no sensitive segments and pass through
 * unchanged, so server-side sourcemap resolution is unaffected.
 *
 * Runs in beforeSend, i.e. AFTER eventFiltersIntegration's allow/deny
 * checks — scrubbing here cannot cause a first-party event to be dropped.
 */
function scrubStackFrameUrls(event: ErrorEvent): void {
  for (const exception of event.exception?.values ?? []) {
    for (const frame of exception.stacktrace?.frames ?? []) {
      if (frame.filename) {
        frame.filename = scrubUrlWithPatterns(frame.filename);
      }
      if (frame.abs_path) {
        frame.abs_path = scrubUrlWithPatterns(frame.abs_path);
      }
    }
  }
}

/**
 * Creates a Sentry beforeSend handler that scrubs sensitive data from events.
 * Handles both URL scrubbing (route-param based) and message scrubbing (regex-based).
 *
 * @internal Exported for testing
 */
function createBeforeSendHandler(router: Router) {
  return (event: ErrorEvent, hint?: EventHint): ErrorEvent | null | Promise<ErrorEvent | null> => {
    // #4286: expected transport outcomes (already-consumed secrets,
    // cancelled requests, client connectivity) are the product working, not
    // a defect. Drop first — no point scrubbing or fingerprinting an event
    // that is about to be discarded.
    if (isExpectedTransportOutcome(hint)) {
      return null;
    }

    if ('secret' in event && event.secret) {
      delete event.secret;
    }

    // Scrub exception messages and standalone messages (regex-based)
    scrubEventMessages(event);

    // Scrub stack-frame filenames/paths (page-URL-attributed frames can carry
    // the secret path)
    scrubStackFrameUrls(event);

    // Collect route-param values for the current route (opt-out-governed).
    const sortedValues = collectCurrentRouteValues(router);

    // Scrub the fields shared with transaction events (request.url, Referer
    // header, transaction) through the single shared entrypoint.
    scrubCommonEventFields(event, sortedValues);

    // Scrub breadcrumb URLs
    if (event.breadcrumbs) {
      event.breadcrumbs = event.breadcrumbs.map((breadcrumb: Breadcrumb) => {
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
        }
        return breadcrumb;
      });
    }

    // Explicit issue grouping LAST, after every scrubber has run: schema
    // validation failures group by schema name, API request errors by
    // method + parameterized path + outcome, so one defect stays one issue
    // across deploys instead of fragmenting on minified bundle hashes.
    // Events matching neither rule keep Sentry's default grouping.
    applyGroupingRules(event, hint);

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
    // event. Without this, events arrive with an empty `url` field. The URL
    // passes through createBeforeSendHandler's scrubbing (route-param values
    // plus the pattern net), so secret identifiers never reach Sentry.
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
    // Note: Sentry 10+ requires sendDefaultPii: true for IP address collection
    // sendDefaultPii: false, // Default is false
    tracePropagationTargets: [
      /^localhost(:\d+)?$/, // Matches localhost with optional port
      // Add host domain regexes only if host is provided. Two patterns, not
      // one combined via `(/|$)`: each ends in an unambiguous terminal token
      // (a literal `$` or a literal `/`) so static analysis (CodeQL
      // js/regex/missing-regexp-anchor) can see the end is anchored, not just
      // reachable via one branch of a group. Same matching behavior as
      // before — host with optional port and nothing else, OR host with
      // optional port followed by a path.
      ...(host
        ? [
            new RegExp(`^https?://([a-z0-9-]+\\.)*${host.replaceAll('.', '\\.')}(:\\d+)?$`, 'i'),
            new RegExp(`^https?://([a-z0-9-]+\\.)*${host.replaceAll('.', '\\.')}(:\\d+)?/`, 'i'),
          ]
        : []),
    ],

    // Only the integrations listed here will be used
    integrations,

    /** Session Replay is disabled. See note above. */
    // replaysSessionSampleRate: 0.1, // Capture 10% of the sessions
    // replaysOnErrorSampleRate: 1.0, // Capture 100% of the errors

    // Scrub sensitive route params from URLs in error events
    beforeSend: createBeforeSendHandler(router),

    // Scrub URLs from performance events (beforeSend does not run for these)
    beforeSendTransaction: createBeforeSendTransactionHandler(router),

    // Scrub sensitive URLs from breadcrumbs at capture time
    beforeBreadcrumb: createBeforeBreadcrumbHandler(router),
    ...config.sentry, // includes dsn, environment, etc.

    // Third-party noise filtering (#4287), consumed by eventFiltersIntegration.
    // Secret links are opened from email/chat clients, so extension and
    // in-app-webview errors are an outsized share of events here. Keep these
    // authoritative if the backend Sentry schema later grows matching fields.
    ignoreErrors: THIRD_PARTY_IGNORE_ERRORS,
    denyUrls: THIRD_PARTY_DENY_URLS,
    allowUrls: FIRST_PARTY_ALLOW_URLS,

    // Build-time release takes precedence over backend config.
    // This ensures frontend errors match the sourcemaps uploaded during this build,
    // which is critical for CDN caching and rolling deploys where the backend
    // might be running a newer release than the cached frontend bundle.
    release: __SENTRY_RELEASE__,
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

  // User context from the server-provided `diagnostics_ref` bootstrap block,
  // on the same two scopes and for the same reason.
  //
  // BOOT ORDERING: this runs inside createDiagnostics(), which appInitializer
  // calls AFTER consumeBootstrapData() and BEFORE app.use(pinia). The
  // bootstrap snapshot is therefore already populated and readable via
  // getBootstrapValue(), while the Pinia store is not yet constructed — hence
  // the service read rather than useBootstrapStore(). Sentry init is NOT
  // moved to accommodate this.
  //
  // If the block is absent (anonymous session, error-page render with no
  // serializers, or an older backend that does not emit it), this is a no-op
  // setUser(null) and the session runs unidentified. The context then arrives
  // lazily through bootstrapStore.update() -> setDiagnosticsActorContext() on
  // the first /bootstrap/me refresh or on login, without re-initializing
  // Sentry.
  applyActorContext([scope, getCurrentScope()] as ActorContextScope[], resolveDiagnosticsRef());

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
