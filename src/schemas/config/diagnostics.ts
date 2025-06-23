// src/schemas/config/diagnostics.ts

import { z } from 'zod/v4';
import { nullableString } from './shared/primitives';

const diagnosticsSentryDefaultsSchema = z.object({
  dsn: nullableString,
  sampleRate: z.number().optional(),
  maxBreadcrumbs: z.number().optional(),
  logErrors: z.boolean().optional(),
});

const diagnosticsSentryBackendSchema = diagnosticsSentryDefaultsSchema.extend({});

const diagnosticsSentryFrontendSchema = diagnosticsSentryDefaultsSchema.extend({
  trackComponents: z.boolean().optional(),
});

const diagnosticsSentrySchema = z.object({
  defaults: diagnosticsSentryDefaultsSchema.optional(),
  backend: diagnosticsSentryBackendSchema.optional(),
  frontend: diagnosticsSentryFrontendSchema.optional(),
});

const sectionDiagnosticsSchema = z.object({
  enabled: z.boolean().default(false),
  sentry: diagnosticsSentrySchema.optional(),
});
