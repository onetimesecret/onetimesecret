// src/types/sentry.ts

import type { Integration } from '@sentry/core';

/**
 * Sentry configuration options
 *
 * Similar but not identical to the ClientOptions interface from the
 * Sentry SDK. We use this interface to pass configuration options
 * from the Ruby backend to the Sentry plugin.
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
    beforeSend?: (event: Event) => Event | null;
    maxBreadcrumbs?: number;
    attachStacktrace?: boolean;
    ignoreErrors?: Array<string | RegExp>;
  };
}
