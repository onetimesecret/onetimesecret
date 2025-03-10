// src/plugins/core/enableDiagnostics.ts

import type { DiagnosticsConfig } from '@/types/diagnostics';
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
import { type ErrorEvent, type Integration } from '@sentry/core';
import * as SentryVue from '@sentry/vue';
import type { App, Plugin } from 'vue';
import type { Router } from 'vue-router';

export const SENTRY_KEY = Symbol('sentry');

interface EnableDiagnosticsOptions {
  // Display domain. This is the domain the user is interacting with, not
  // the Sentry domain. Same meaning as `display_domain`.
  host: string;
  // Sentry configuration from backend
  config: DiagnosticsConfig;
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
    tracePropagationTargets: [
      'localhost',
      new RegExp(`^https:\\/\\/[^/]+${host.replace('.', '\\.')}`),
    ],

    // Only the integrations listed here will be used
    integrations,

    /** Session Replay is disabled. See note above. */
    // replaysSessionSampleRate: 0.1, // Capture 10% of the sessions
    // replaysOnErrorSampleRate: 1.0, // Capture 100% of the errors

    // This is called for message and error events
    beforeSend(event: ErrorEvent): ErrorEvent | null | Promise<ErrorEvent | null> {
      if ('secret' in event && event.secret) {
        delete event.secret;
      }
      return event;
    },
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
      // Provide Sentry instance using symbol key
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
