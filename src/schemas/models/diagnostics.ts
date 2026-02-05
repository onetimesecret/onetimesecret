// src/schemas/models/diagnostics.ts

/**
 * Runtime Diagnostics Configuration Schema
 *
 * This schema validates the Sentry configuration passed from the Ruby backend
 * to the Vue frontend at runtime. This is different from the YAML config
 * validation in schemas/config/section/diagnostics.ts which validates the
 * server-side configuration file.
 *
 * @see https://github.com/getsentry/sentry-javascript/blob/8.54.0/packages/core/src/types-hoist/options.ts
 */

import type { ErrorEvent, Integration } from '@sentry/core';
import { z } from 'zod';

/**
 * Sentry client configuration schema
 *
 * Some fields like `integrations` and `beforeSend` are functions/complex types
 * that cannot be validated by Zod at runtime - they use z.unknown() to allow
 * any value while maintaining type safety through the inferred type.
 */
export const sentryConfigSchema = z.object({
  dsn: z.string(),

  /**
   * Specifies whether this SDK should send events to Sentry.
   * Defaults to true.
   */
  enabled: z.boolean().optional(),

  /**
   * Enable debug functionality in the SDK itself
   */
  debug: z.boolean().optional(),

  environment: z.string().optional(),
  release: z.string().optional(),
  tracesSampleRate: z.number().optional(),

  /**
   * Sentry integrations - complex type, validated as unknown
   */
  integrations: z.unknown().optional(),

  /**
   * beforeSend callback - function type, validated as unknown
   */
  beforeSend: z.unknown().optional(),

  maxBreadcrumbs: z.number().optional(),
  attachStacktrace: z.boolean().optional(),

  /**
   * Array of error patterns to ignore - can contain strings or RegExp
   */
  ignoreErrors: z.array(z.unknown()).optional(),

  /**
   * Array of URL patterns to blacklist - can contain strings or RegExp
   */
  blacklistUrls: z.array(z.unknown()).optional(),

  logErrors: z.literal(true),
  trackComponents: z.literal(true),
});

/**
 * Complete diagnostics configuration schema
 */
export const diagnosticsConfigSchema = z.object({
  sentry: sentryConfigSchema,
});

/**
 * Inferred type for Sentry configuration with proper Sentry types
 *
 * The Zod schema uses z.unknown() for complex types (integrations, beforeSend, etc.)
 * that cannot be validated at runtime. We override those fields here with proper
 * Sentry types to maintain type safety in consuming code.
 */
export type SentryConfig = Omit<
  z.infer<typeof sentryConfigSchema>,
  'integrations' | 'beforeSend' | 'ignoreErrors' | 'blacklistUrls'
> & {
  integrations?: Integration[];
  beforeSend?: (event: ErrorEvent) => ErrorEvent | null | Promise<ErrorEvent | null>;
  ignoreErrors?: Array<string | RegExp>;
  blacklistUrls?: Array<string | RegExp>;
};

/**
 * Inferred type for diagnostics configuration
 */
export type DiagnosticsConfig = {
  sentry: SentryConfig;
};
