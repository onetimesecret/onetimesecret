// src/schemas/config/section/diagnostics.ts

/**
 * Diagnostics Configuration Schema
 *
 * Maps to the `diagnostics:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';
import { nullableString } from '../shared/primitives';

/**
 * Sentry defaults configuration
 */
const diagnosticsSentryDefaultsSchema = z.object({
  dsn: nullableString,
  sampleRate: z.union([z.string(), z.number()]).optional(),
  maxBreadcrumbs: z.union([z.string(), z.number()]).optional(),
  logErrors: z.boolean().default(true),
});

/**
 * Sentry backend configuration
 */
const diagnosticsSentryBackendSchema = diagnosticsSentryDefaultsSchema.extend({});

/**
 * Sentry frontend configuration
 */
const diagnosticsSentryFrontendSchema = diagnosticsSentryDefaultsSchema.extend({
  trackComponents: z.boolean().default(true),
});

/**
 * Sentry configuration
 */
const diagnosticsSentrySchema = z.object({
  defaults: diagnosticsSentryDefaultsSchema.optional(),
  backend: diagnosticsSentryBackendSchema.optional(),
  frontend: diagnosticsSentryFrontendSchema.optional(),
});

/**
 * Complete diagnostics schema
 */
const diagnosticsSchema = z.object({
  enabled: z.boolean().default(false),
  sentry: diagnosticsSentrySchema.optional(),
});

export {
  diagnosticsSchema,
  diagnosticsSentrySchema,
  diagnosticsSentryDefaultsSchema,
  diagnosticsSentryBackendSchema,
  diagnosticsSentryFrontendSchema,
};
