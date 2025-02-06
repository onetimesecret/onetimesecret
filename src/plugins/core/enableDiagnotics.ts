// src/plugins/core/enableDiagnotics.ts

/**
 *
 */
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

interface EnableDiagnosticsOptions {
  config: DiagnosticsConfig;
  router: Router;
}

/**
 * Vue plugin that initializes Sentry error tracking and monitoring.
 * Provides centralized error handling, performance monitoring, and session replay.
 *
 * @plugin
 * @param {App} app - Vue application instance
 * @param {EnableDiagnosticsOptions} options - Configuration options
 * @param {DiagnosticsConfig} options.config - Sentry configuration from backend
 * @param {Router} options.router - Vue Router instance for route tracking
 *
 * @example
 * ```ts
 * app.use(EnableDiagnostics, {
 *   config: window.diagnostics,
 *   router: router
 * });
 * ```
 *
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/options/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/best-practices/sentry-testkit/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/sourcemaps/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/integrations/browserapierrors/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/features/
 */
export const EnableDiagnostics: Plugin = {
  install(app: App, options: EnableDiagnosticsOptions) {
    const { config, router } = options;

    console.debug('[EnableDiagnostics] sentry:', config['sentry']);

    // @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/tree-shaking/
    const integrations: Integration[] = [
      breadcrumbsIntegration(),
      globalHandlersIntegration(),
      linkedErrorsIntegration(),
      dedupeIntegration(),
      SentryVue.browserTracingIntegration({ router }),
      SentryVue.replayIntegration(),
    ];

    // All options you normally pass to Sentry.init. The values
    // here are the defaults if not provided in options.
    const sentryOptions = {
      debug: DEBUG,

      sampleRate: 0.001, // just a trickle by default. More than none.

      transport: makeFetchTransport,
      stackParser: defaultStackParser,

      // Tracing
      tracesSampleRate: 0.01, //  Capture 1% of the transactions
      // Controls for which URLs distributed tracing should be enabled
      tracePropagationTargets: ['localhost', /^https:\/\/\*\.onetimesecret\.com\//],

      // Session Replay
      replaysSessionSampleRate: 0.1, // Capture 10% of the sessions
      replaysOnErrorSampleRate: 1.0, // Capture 100% of the errors

      // Only the integrations listed here will be used
      integrations,

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

    // Make the Sentry client available to the Vue app
    app.provide('sentry', { client, scope });
  },
};
