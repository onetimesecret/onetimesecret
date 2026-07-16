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
  type Integration,
  type TransactionEvent,
} from '@sentry/core';
import * as SentryVue from '@sentry/vue';
import type { App, Plugin } from 'vue';
import type { Router, RouteMeta as VueRouteMeta } from 'vue-router';
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
 * Collects the route-param VALUES to redact for the route a *transaction*
 * event belongs to. Transactions (pageload/navigation) can still be in flight
 * when the user navigates away, so `router.currentRoute` may describe a
 * different route than the one the event's URLs point at — reading the live
 * route there would silently skip the value layer. Instead, resolve the route
 * from the transaction's own `request.url`, and fall back to the current
 * route only when no URL is present or resolution fails.
 */
function collectTransactionRouteValues(router: Router, event: TransactionEvent): string[] {
  const url = event.request?.url;
  if (url) {
    try {
      // router.resolve wants an in-app location, not a full URL. Use a
      // synthetic base so bare paths parse too; the base is discarded.
      const parsed = new URL(url, 'http://_');
      const resolved = router.resolve(parsed.pathname + parsed.search + parsed.hash);
      return collectRouteParamValues(resolved as ResolvedRouteLike);
    } catch {
      // Fall through to the current-route fallback below.
    }
  }
  return collectCurrentRouteValues(router);
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
 *
 * Event-kind-specific fields (error breadcrumbs, transaction spans) are handled
 * by the respective callers, not here.
 */
function scrubCommonEventFields(
  event: ErrorEvent | TransactionEvent,
  sortedValues: string[]
): void {
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
      // Add host domain regex only if host is provided.
      // Properly anchored: requires host to be at the end of the domain portion,
      // either at end of string or followed by / or :port
      ...(host
        ? [new RegExp(`^https?://([a-z0-9-]+\\.)*${host.replaceAll('.', '\\.')}(:\\d+)?(/|$)`, 'i')]
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

    // Build-time release takes precedence over backend config.
    // This ensures frontend errors match the sourcemaps uploaded during this build,
    // which is critical for CDN caching and rolling deploys where the backend
    // might be running a newer release than the cached frontend bundle.
    release: __SENTRY_RELEASE__,
  };

  console.debug('[EnableDiagnostics] sentryOptions:', sentryOptions);

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
  router.afterEach((to) => {
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
          client.close(2000).then(() => {
            original.call(this);
          });
        })(app.unmount);
    },
  };
}
