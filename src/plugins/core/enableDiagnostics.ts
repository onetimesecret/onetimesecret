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
 * Scrubs sensitive route parameter values from a URL string.
 *
 * @param url - The URL string to scrub
 * @param params - Route params object with values to redact
 * @param paramsToScrub - Which params to scrub: undefined/true = all, string[] = named only
 * @returns The scrubbed URL with sensitive values replaced by [REDACTED]
 */
function scrubSensitiveParams(
  url: string,
  params: Record<string, string | string[]>,
  paramsToScrub: RouteMeta['sentryScrubParams']
): string {
  if (!url || !params || Object.keys(params).length === 0) {
    return url;
  }

  let scrubbedUrl = url;

  for (const [paramName, paramValue] of Object.entries(params)) {
    // Skip if we're only scrubbing specific params and this isn't one of them
    if (Array.isArray(paramsToScrub) && !paramsToScrub.includes(paramName)) {
      continue;
    }

    // Handle both string and string[] param values
    const values = Array.isArray(paramValue) ? paramValue : [paramValue];
    for (const value of values) {
      if (value) {
        // Escape special regex characters in the value
        const escapedValue = value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        // Replace all occurrences of the param value in the URL
        scrubbedUrl = scrubbedUrl.replace(new RegExp(escapedValue, 'g'), '[REDACTED]');
      }
    }
  }

  return scrubbedUrl;
}

/**
 * Creates a Sentry beforeSend handler that scrubs sensitive route params from events.
 * Extracted to keep createDiagnostics under the max-lines-per-function limit.
 */
function createBeforeSendHandler(router: Router) {
  return (event: ErrorEvent): ErrorEvent | null | Promise<ErrorEvent | null> => {
    if ('secret' in event && event.secret) {
      delete event.secret;
    }

    // Scrub sensitive route params from URLs based on route metadata
    const currentRoute = router.currentRoute.value;
    const sentryScrubParams = currentRoute.meta.sentryScrubParams as RouteMeta['sentryScrubParams'];

    // If explicitly opted out, return event without scrubbing
    if (sentryScrubParams === false) {
      return event;
    }

    // Get route params to scrub (all params by default)
    const params = currentRoute.params as Record<string, string | string[]>;
    if (!params || Object.keys(params).length === 0) {
      return event;
    }

    // Scrub event.request?.url
    if (event.request?.url) {
      event.request.url = scrubSensitiveParams(event.request.url, params, sentryScrubParams);
    }

    // Scrub event.transaction
    if (event.transaction) {
      event.transaction = scrubSensitiveParams(event.transaction, params, sentryScrubParams);
    }

    // Scrub breadcrumb URLs
    if (event.breadcrumbs) {
      event.breadcrumbs = event.breadcrumbs.map((breadcrumb: Breadcrumb) => {
        if (breadcrumb.data) {
          if (breadcrumb.data.url) {
            breadcrumb.data.url = scrubSensitiveParams(
              breadcrumb.data.url as string,
              params,
              sentryScrubParams
            );
          }
          if (breadcrumb.data.to) {
            breadcrumb.data.to = scrubSensitiveParams(
              breadcrumb.data.to as string,
              params,
              sentryScrubParams
            );
          }
          if (breadcrumb.data.from) {
            breadcrumb.data.from = scrubSensitiveParams(
              breadcrumb.data.from as string,
              params,
              sentryScrubParams
            );
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
    sampleRate: 0.001,
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
    ...config.sentry, // includes dsn, environment, release, etc.
  };

  console.debug('[EnableDiagnostics] sentryOptions:', sentryOptions);

  const client = new BrowserClient(sentryOptions);
  const scope = new Scope();
  scope.setClient(client);

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
