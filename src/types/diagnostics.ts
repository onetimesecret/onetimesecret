// src/types/diagnostics.ts

import type { Integration, ErrorEvent } from '@sentry/core';

/**
 * Sentry configuration options
 *
 * Similar but not identical to the ClientOptions interface from the
 * Sentry SDK. We use this interface to pass configuration options
 * from the Ruby backend to the Sentry plugin.
 *
 * Similar to ClientOptions from @sentry/vue but includes only the options
 * we support configuring via our YAML config. All options set in
 * config.yaml :frontend section are passed directly to Sentry client.
 *
 * When adding new options to config.yaml :frontend section, they must be
 * added here to maintain type safety.
 *
 * Could be implemented as a partial of ClientOptions, once we have
 * a better understanding of what all we want to be doing.
 *
 * @see https://github.com/getsentry/sentry-javascript/blob/8.54.0/packages/core/src/types-hoist/options.ts
 *
 */
export interface DiagnosticsConfig {
  sentry: {
    dsn: string;

    /**
     * Specifies whether this SDK should send events to Sentry.
     * Defaults to true.
     */
    enabled?: boolean;

    /**
     * Enable debug functionality in the SDK itself
     */
    debug?: boolean;

    environment?: string;
    release?: string;
    tracesSampleRate?: number;
    integrations?: Integration[];
    beforeSend?: (event: ErrorEvent) => ErrorEvent | null | Promise<ErrorEvent | null>;
    maxBreadcrumbs?: number;
    attachStacktrace?: boolean;
    ignoreErrors?: Array<string | RegExp>;
    blacklistUrls?: Array<string | RegExp>;

    logErrors: true;
    trackComponents: true;
  };
}
