// src/schemas/shapes/config/section/diagnostics.ts

/**
 * Diagnostics Configuration Shape
 *
 * Adds runtime defaults on top of the type-only diagnostics contract.
 *
 * @see src/schemas/contracts/config/section/diagnostics.ts
 */

import {
  diagnosticsSchema,
  diagnosticsSentrySchema,
  diagnosticsSentryDefaultsSchema,
  diagnosticsSentryBackendSchema,
  diagnosticsSentryFrontendSchema,
} from '@/schemas/contracts/config/section/diagnostics';
import { augment } from '@/schemas/utils/augment';

export {
  diagnosticsSchema,
  diagnosticsSentrySchema,
  diagnosticsSentryDefaultsSchema,
  diagnosticsSentryBackendSchema,
  diagnosticsSentryFrontendSchema,
};

const diagnosticsSentryDefaultsShape = augment(diagnosticsSentryDefaultsSchema, {
  logErrors: (b) => b.default(true),
});

const diagnosticsSentryBackendShape = augment(diagnosticsSentryBackendSchema, {
  logErrors: (b) => b.default(true),
});

const diagnosticsSentryFrontendShape = augment(diagnosticsSentryFrontendSchema, {
  logErrors: (b) => b.default(true),
  trackComponents: (b) => b.default(true),
});

const diagnosticsSentryShape = augment(diagnosticsSentrySchema, {
  defaults: { logErrors: (b) => b.default(true) },
  backend: { logErrors: (b) => b.default(true) },
  frontend: {
    logErrors: (b) => b.default(true),
    trackComponents: (b) => b.default(true),
  },
});

const diagnosticsShape = augment(diagnosticsSchema, {
  enabled: (b) => b.default(false),
  sentry: {
    defaults: { logErrors: (b) => b.default(true) },
    backend: { logErrors: (b) => b.default(true) },
    frontend: {
      logErrors: (b) => b.default(true),
      trackComponents: (b) => b.default(true),
    },
  },
});

export {
  diagnosticsShape,
  diagnosticsSentryShape,
  diagnosticsSentryDefaultsShape,
  diagnosticsSentryBackendShape,
  diagnosticsSentryFrontendShape,
};
