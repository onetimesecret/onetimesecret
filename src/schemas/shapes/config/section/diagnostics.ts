// src/schemas/shapes/config/section/diagnostics.ts

/**
 * Diagnostics Configuration Shape
 *
 * Adds runtime defaults on top of the type-only diagnostics contract.
 *
 * @see src/schemas/contracts/config/section/diagnostics.ts
 */

import { z } from 'zod';
import { nullableString } from '@/schemas/contracts/config/shared/primitives';

export {
  diagnosticsSchema,
  diagnosticsSentrySchema,
  diagnosticsSentryDefaultsSchema,
  diagnosticsSentryBackendSchema,
  diagnosticsSentryFrontendSchema,
} from '@/schemas/contracts/config/section/diagnostics';

const diagnosticsSentryDefaultsShape = z.object({
  dsn: nullableString,
  sampleRate: z.union([z.string(), z.number()]).optional(),
  maxBreadcrumbs: z.union([z.string(), z.number()]).optional(),
  logErrors: z.boolean().default(true),
});

const diagnosticsSentryBackendShape = diagnosticsSentryDefaultsShape.extend({});

const diagnosticsSentryFrontendShape = diagnosticsSentryDefaultsShape.extend({
  trackComponents: z.boolean().default(true),
});

const diagnosticsSentryShape = z.object({
  defaults: diagnosticsSentryDefaultsShape.optional(),
  backend: diagnosticsSentryBackendShape.optional(),
  frontend: diagnosticsSentryFrontendShape.optional(),
});

const diagnosticsShape = z.object({
  enabled: z.boolean().default(false),
  sentry: diagnosticsSentryShape.optional(),
});

export {
  diagnosticsShape,
  diagnosticsSentryShape,
  diagnosticsSentryDefaultsShape,
  diagnosticsSentryBackendShape,
  diagnosticsSentryFrontendShape,
};
