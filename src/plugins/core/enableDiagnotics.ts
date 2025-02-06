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
  type ErrorEvent,
} from '@sentry/browser';
import * as SentryVue from '@sentry/vue';
import type { App, Plugin } from 'vue';
import type { Router } from 'vue-router';

/**
 * Global error handling plugin for Vue 3 applications that connects
 * with Vue's built-in error handling system
 *
 * @description Provides a centralized error handling mechanism for the entire Vue application
 * @param {App} app - Vue application instance
 * @param {BrowserClient} [options={}] - Plugin options
 *
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/options/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/best-practices/sentry-testkit/
 *
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/tree-shaking/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/sourcemaps/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/configuration/integrations/browserapierrors/
 * @see https://docs.sentry.io/platforms/javascript/guides/vue/features/
 */
export const EnableDiagnostics: Plugin = {
  install(app: App, options: DiagnosticsConfig, router: Router) {
    // All options you normally pass to Sentry.init. The values
    // here are the defaults if not provided in options.
    const clientOptions = {
      debug: DEBUG,

      trackComponents: true, // vue-specific
      logErrors: true,

      sampleRate: 1.0,
      maxBreadcrumbs: 20,

      transport: makeFetchTransport,
      stackParser: defaultStackParser,

      // Tracing
      tracesSampleRate: 1.0, //  Capture 100% of the transactions
      // Controls for which URLs distributed tracing should be enabled
      tracePropagationTargets: ['localhost', /^https:\/\/\*\.onetimesecret\.com\//],
      // Session Replay
      replaysSessionSampleRate: 0.1, // Capture 10% of the sessions
      replaysOnErrorSampleRate: 1.0, // Capture 100% of the errors

      // Only the integrations listed here will be used
      integrations: [
        breadcrumbsIntegration(),
        globalHandlersIntegration(),
        linkedErrorsIntegration(),
        dedupeIntegration(),

        SentryVue.browserTracingIntegration({ router }),
        SentryVue.replayIntegration(),
      ],

      // This is called for message and error events
      beforeSend(event: ErrorEvent): ErrorEvent | null | Promise<ErrorEvent | null> {
        if ('secret' in event && event.secret) {
          delete event.secret;
        }
        return event;
      },

      ...options, // includes dsn, environment, release, etc.
    };
    const client = new BrowserClient(clientOptions);
    const scope = new Scope();
    scope.setClient(client);

    // Initialize the Sentry client. This is equivalent to calling
    // Sentry.init() with the options provided above.
    client.init(); // after setting the client on the scope

    // Make the Sentry client available to the Vue app
    app.provide('sentry', { client, scope });
  },
};
