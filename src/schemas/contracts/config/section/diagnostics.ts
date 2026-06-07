// src/schemas/contracts/config/section/diagnostics.ts

/**
 * Diagnostics Configuration Schema
 *
 * Maps to the `diagnostics:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults belong in `shapes/config/section/diagnostics.ts`.
 */

import { z } from 'zod';
import { nullableString } from '../shared/primitives';

/**
 * Sentry defaults configuration
 */
const diagnosticsSentryDefaultsSchema = z.object({
  dsn: nullableString,
  sampleRate: z.union([z.string(), z.number()]).optional(),
  maxBreadcrumbs: z.union([z.string(), z.number()]).optional(),
  logErrors: z.boolean().optional(),
});

/**
 * Sentry backend configuration
 */
const diagnosticsSentryBackendSchema = diagnosticsSentryDefaultsSchema.extend({});

/**
 * Sentry frontend configuration
 */
const diagnosticsSentryFrontendSchema = diagnosticsSentryDefaultsSchema.extend({
  trackComponents: z.boolean().optional(),
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
  enabled: z.boolean().optional(),
  sentry: diagnosticsSentrySchema.optional(),
});

export {
  diagnosticsSchema,
  diagnosticsSentrySchema,
  diagnosticsSentryDefaultsSchema,
  diagnosticsSentryBackendSchema,
  diagnosticsSentryFrontendSchema,
};
