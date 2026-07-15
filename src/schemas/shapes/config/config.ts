// src/schemas/shapes/config/config.ts

/**
 * Application Configuration Shape
 *
 * Composes the per-section shapes into the runtime/static/mutable/legacy
 * config schemas consumed by the JSON Schema generator and the Ruby CLI
 * validators (`bin/ots config validate`).
 *
 * The contract-side `config.ts` is a parallel type-only composition; this
 * file is the one that carries defaults and value constraints.
 *
 * @see src/schemas/contracts/config/config.ts
 */

import { z } from 'zod';

import { siteShape } from './section/site';
import { storageShape, redisShape } from './section/storage';
import { emailerShape, mailShape, mailConnectionShape, mailValidationShape } from './section/mail';
import { diagnosticsShape } from './section/diagnostics';
import { featuresShape } from './section/features';
import { capabilitiesSchema } from './section/capabilities';
import { i18nShape } from './section/i18n';
import { developmentShape } from './section/development';
import { experimentalShape } from './section/experimental';
import { userInterfaceShape, apiShape } from './section/ui';
import { limitsSchema } from './section/limits';
import { secretOptionsShape } from './section/secret_options';
import { jobsShape } from './section/jobs';

// Re-export shape symbols for direct access via this module
export {
  siteShape,
  storageShape,
  redisShape,
  emailerShape,
  mailShape,
  mailConnectionShape,
  mailValidationShape,
  diagnosticsShape,
  featuresShape,
  capabilitiesSchema as capabilitiesShape,
  i18nShape,
  developmentShape,
  experimentalShape,
  userInterfaceShape,
  apiShape,
  limitsSchema as limitsShape,
  secretOptionsShape,
  jobsShape,
};

// Re-export contract types and API response schemas — these live on the
// contract side so consumers can keep their existing imports working.
export {
  booleanOrString,
  numberOrString,
  apiInterfaceSchema,
  apiSecretOptionsSchema,
  apiEmailerSchema,
  apiMailSchema,
  apiDiagnosticsSchema,
  apiAuthenticationSchema,
  apiLoggingSchema,
  apiBillingSchema,
  apiFeaturesSchema,
  systemSettingsSchema,
  systemSettingsDetailsSchema,
  staticConfigSchema,
  mutableConfigSchema,
  runtimeConfigSchema,
  legacyStaticConfigSchema,
  staticMailSchema,
  mutableMailSchema,
  loggingSchema,
} from '@/schemas/contracts/config/config';

export type {
  StaticConfig,
  MutableConfig,
  RuntimeConfig,
  LegacyStaticConfig,
  SystemSettings,
  SystemSettingsDetails,
} from '@/schemas/contracts/config/config';

/**
 * Combined mail shape for static config
 */
const staticMailShape = z.object({
  connection: mailConnectionShape,
  validation: z.object({
    defaults: mailValidationShape.optional(),
  }),
});

/**
 * Mutable mail validation shape
 */
const mutableMailShape = z.object({
  validation: z.object({
    recipients: mailValidationShape.optional(),
    accounts: mailValidationShape.optional(),
  }),
});

/**
 * Simple logging shape for static config
 */
const simpleLoggingShape = z.object({
  http_requests: z.boolean().default(true),
});

/**
 * Static configuration shape — strict YAML validation for `bin/ots config
 * validate` and JSON Schema generation. Composes the per-section shapes so
 * defaults and bounds flow through.
 */
const staticConfigShape = z.object({
  site: siteShape,
  features: featuresShape.optional(),
  redis: redisShape.optional(),
  emailer: emailerShape.optional(),
  mail: mailShape.optional(),
  jobs: jobsShape.optional(),
  internationalization: i18nShape.optional(),
  diagnostics: diagnosticsShape.optional(),
  development: developmentShape.optional(),
  experimental: experimentalShape.optional(),
});

/**
 * Mutable configuration shape — settings reloadable at runtime.
 */
const mutableConfigShape = z.object({
  ui: userInterfaceShape.optional(),
  api: apiShape.optional(),
  secret_options: secretOptionsShape.optional(),
  mail: mutableMailShape.optional(),
  features: featuresShape.optional(),
  limits: limitsSchema.optional(),
});

/**
 * Runtime configuration shape — static merged on top of mutable.
 */
const runtimeConfigShape = z.object({
  ...mutableConfigShape.shape,
  ...staticConfigShape.shape,
});

/**
 * Legacy static configuration shape for backward compatibility.
 */
const legacyStaticConfigShape = z.object({
  site: siteShape,
  storage: storageShape.optional(),
  features: featuresShape.optional(),
  capabilities: capabilitiesSchema.optional(),
  mail: staticMailShape.optional(),
  logging: simpleLoggingShape.optional(),
  i18n: i18nShape.optional(),
  development: developmentShape.optional(),
  diagnostics: diagnosticsShape.optional(),
});

export {
  staticConfigShape,
  mutableConfigShape,
  runtimeConfigShape,
  legacyStaticConfigShape,
  staticMailShape,
  mutableMailShape,
  simpleLoggingShape,
};
