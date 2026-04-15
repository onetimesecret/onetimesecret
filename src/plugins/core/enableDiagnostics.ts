// src/plugins/core/enableDiagnostics.ts

import { getBootstrapValue } from '@/services/bootstrap.service';
import { initDiagnostics } from '@/services/diagnostics.service';
import type { DiagnosticsConfig } from '@/types/diagnostics';
import type { RouteMeta } from '@/types/router';
import { DEBUG } from '@/utils/debug';
import { collectValuesToRedact, scrubUrlWithValues } from './diagnostics/urlScrubbing';
// Re-export scrubbing utilities from dependency-free module for backward compatibility
export {
  EMAIL_PATTERN,
  SENSITIVE_PATH_PATTERN,
  VERIFIABLE_ID_PATTERN,
  scrubSensitiveStrings,
  scrubUrlWithPatterns,
} from './diagnostics/scrubbers';
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

// Import functions for local use (patterns are re-exported above for external consumers)
import { scrubSensitiveStrings, scrubUrlWithPatterns } from './diagnostics/scrubbers';

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
function createBeforeSendHandler(router: Router) {
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

  // Add jurisdiction tag for region-specific filtering in Sentry
  // Use bootstrap value directly since Pinia is not yet installed when createDiagnostics() is called
  const regions = getBootstrapValue('regions');
  const jurisdictionId =
    typeof regions?.current_jurisdiction === 'string'
      ? regions.current_jurisdiction.toLowerCase()
      : null;
  if (jurisdictionId) {
    scope.setTag('jurisdiction', jurisdictionId);
  }

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
