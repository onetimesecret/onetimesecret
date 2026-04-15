// src/plugins/core/enableDiagnostics.ts

import { initDiagnostics } from '@/services/diagnostics.service';
import type { DiagnosticsConfig } from '@/types/diagnostics';
import type { RouteMeta } from '@/types/router';
import { DEBUG } from '@/utils/debug';
import {
  BrowserClient,
  Scope,
  breadcrumbsIntegration,
  dedupeIntegration,
  defaultStackParser,
  globalHandlersIntegration,
  linkedErrorsIntegration,
  makeFetchTransport,
} from '@sentry/browser';
import { type Breadcrumb, type ErrorEvent, type Integration } from '@sentry/core';
import * as SentryVue from '@sentry/vue';
import type { App, Plugin } from 'vue';
import type { Router } from 'vue-router';

export const SENTRY_KEY = Symbol('sentry');

/**
 * Collects param values to redact from route params, sorted by length descending.
 * Sorting ensures longer strings are replaced before shorter ones to avoid
 * corrupting overlapping matches (e.g., 'foobar' before 'foo').
 *
 * @param params - Route params object with values to redact
 * @param paramsToScrub - Which params to scrub: undefined/true = all, string[] = named only
 * @returns Array of values sorted by length descending, ready for scrubbing
 *
 * @internal Exported for testing
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
 *
 * @internal Exported for testing
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

/**
 * Regex pattern for sensitive path segments in HTTP requests.
 * Matches: /secret/, /private/, /receipt/, /incoming/ followed by an identifier.
 * Does NOT include /colonel/ as those routes explicitly opt out of scrubbing.
 *
 * @internal Exported for testing
 */
export const SENSITIVE_PATH_PATTERN = /\/(secret|private|receipt|incoming)\/([a-zA-Z0-9]+)/gi;

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
 * @param text - The string to scrub
 * @returns The scrubbed string with sensitive data replaced
 *
 * @internal Exported for testing
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

  // Scrub sensitive path patterns (in case exception message contains URLs/paths)
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  return result;
}

/**
 * Scrubs sensitive identifiers from a URL path using regex patterns.
 * Used for HTTP breadcrumbs where we don't have route context.
 *
 * @param url - The URL string to scrub
 * @returns The scrubbed URL with sensitive identifiers replaced by [REDACTED]
 *
 * @internal Exported for testing
 */
export function scrubUrlWithPatterns(url: string): string {
  if (!url || typeof url !== 'string') {
    return url;
  }

  let result = url;

  // First pass: scrub known sensitive path patterns
  result = result.replace(SENSITIVE_PATH_PATTERN, '/$1/[REDACTED]');

  // Second pass: scrub any remaining 62-char verifiable IDs
  result = result.replace(VERIFIABLE_ID_PATTERN, '[REDACTED]');

  return result;
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
export function createBeforeBreadcrumbHandler(router: Router) {
  return (breadcrumb: Breadcrumb): Breadcrumb | null => {
    const category = breadcrumb.category;

    // Handle navigation breadcrumbs using route resolution
    if (category === 'navigation' && breadcrumb.data) {
      const scrubNavigationUrl = (path: string): string => {
        if (!path || typeof path !== 'string') {
          return path;
        }

        try {
          const resolved = router.resolve(path);
          const sentryScrubParams = resolved.meta.sentryScrubParams as
            | RouteMeta['sentryScrubParams']
            | undefined;

          // Explicitly opted out of scrubbing
          if (sentryScrubParams === false) {
            return path;
          }

          const params = resolved.params as Record<string, string | string[]>;
          if (!params || Object.keys(params).length === 0) {
            return path;
          }

          const sortedValues = collectValuesToRedact(params, sentryScrubParams);
          if (sortedValues.length === 0) {
            return path;
          }

          // Use centralized utility for consistency and hostname protection
          return scrubUrlWithValues(path, sortedValues);
        } catch {
          // If resolution fails, apply fallback pattern scrubbing
          return scrubUrlWithPatterns(path);
        }
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
export function createBeforeSendHandler(router: Router) {
  return (event: ErrorEvent): ErrorEvent | null | Promise<ErrorEvent | null> => {
    if ('secret' in event && event.secret) {
      delete event.secret;
    }

    // Scrub exception messages and standalone messages (regex-based)
    scrubEventMessages(event);

    // Scrub sensitive route params from URLs based on route metadata
    const currentRoute = router.currentRoute.value;
    const sentryScrubParams = currentRoute.meta.sentryScrubParams as RouteMeta['sentryScrubParams'];

    // If explicitly opted out, return event without URL scrubbing
    // (exception message scrubbing above still applies)
    if (sentryScrubParams === false) {
      return event;
    }

    // Get route params to scrub (all params by default)
    const params = currentRoute.params as Record<string, string | string[]>;
    if (!params || Object.keys(params).length === 0) {
      return event;
    }

    // Collect values to redact once, reuse for all URL scrubbing
    const sortedValues = collectValuesToRedact(params, sentryScrubParams);
    if (sortedValues.length === 0) {
      return event;
    }

    // Scrub event.request?.url
    if (event.request?.url) {
      event.request.url = scrubUrlWithValues(event.request.url, sortedValues);
    }

    // Scrub event.transaction
    if (event.transaction) {
      event.transaction = scrubUrlWithValues(event.transaction, sortedValues);
    }

    // Scrub breadcrumb URLs (values already computed, just apply)
    if (event.breadcrumbs) {
      event.breadcrumbs = event.breadcrumbs.map((breadcrumb: Breadcrumb) => {
        if (breadcrumb.data) {
          if (breadcrumb.data.url) {
            breadcrumb.data.url = scrubUrlWithValues(breadcrumb.data.url as string, sortedValues);
          }
          if (breadcrumb.data.to) {
            breadcrumb.data.to = scrubUrlWithValues(breadcrumb.data.to as string, sortedValues);
          }
          if (breadcrumb.data.from) {
            breadcrumb.data.from = scrubUrlWithValues(breadcrumb.data.from as string, sortedValues);
          }
        }
        return breadcrumb;
      });
    }

    return event;
  };
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
    debug: DEBUG,
    // sampleRate controls error event sampling (0.0-1.0). Default to 1.0 to capture
    // all errors - errors are low-volume and represent actual problems worth tracking.
    // This differs from tracesSampleRate (below) which controls performance trace
    // sampling and should remain low since traces are high-volume.
    sampleRate: 1.0,
    transport: makeFetchTransport,
    stackParser: defaultStackParser,
    tracesSampleRate: 0.01,
    // Note: Sentry 10+ requires sendDefaultPii: true for IP address collection
    // sendDefaultPii: false, // Default is false
    tracePropagationTargets: [
      /^localhost(:\d+)?$/, // Matches localhost with optional port
      // Add host domain regex only if host is provided
      ...(host ? [new RegExp(`^https?:\/\/[^/]+${host.replace('.', '\\.')}`)] : []),
    ],

    // Only the integrations listed here will be used
    integrations,

    /** Session Replay is disabled. See note above. */
    // replaysSessionSampleRate: 0.1, // Capture 10% of the sessions
    // replaysOnErrorSampleRate: 1.0, // Capture 100% of the errors

    // Scrub sensitive route params from URLs in error events
    beforeSend: createBeforeSendHandler(router),

    // Scrub sensitive URLs from breadcrumbs at capture time
    beforeBreadcrumb: createBeforeBreadcrumbHandler(router),
    ...config.sentry, // includes dsn, environment, release, etc.
  };

  console.debug('[EnableDiagnostics] sentryOptions:', sentryOptions);

  const client = new BrowserClient(sentryOptions);
  const scope = new Scope();
  scope.setClient(client);

  // Set default service tag for all events from this frontend app
  // @see https://github.com/onetimesecret/onetimesecret/issues/2964
  scope.setTag('service', 'web');

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
