// src/schemas/config/index.ts

/**
 * Configuration Schema Architecture
 *
 * This module defines two complementary schema types for application configuration:
 *
 * Static Config Schema (staticConfigSchema):
 * - Defines infrastructure topology and system capabilities
 * - Establishes the bounds of what's possible in the application
 * - Represents bootstrap configuration that sets up foundational services
 *
 * Mutable Settings Schema (mutableSettingsSchema):
 * - Defines business policies and runtime behavior
 * - Operates within the bounds established by static configuration
 * - Represents dynamic settings that can be modified during operation
 *
 * Static + Mutable -> Runtime Config.
 *
 * Design Principle:
 * Separate concerns during authoring, unify for consumption. The configuration
 * system merges these schemas at runtime, with merge priority ensuring that
 * runtime policies cannot break infrastructure constraints. This creates a
 * capability-based configuration where the runtime settings object becomes
 * the operational source of truth while respecting both infrastructure
 * topology and business rules.
 */

import { z } from 'zod/v4';
import { nullableString } from './shared/primitives';

import { siteSchema } from './section/site';
import { storageSchema } from './section/storage';
import { mailConnectionSchema, mailValidationSchema } from './section/mail';
import { diagnosticsSchema } from './section/diagnostics';

const apiSchema = z.object({
  enabled: z.boolean().default(true),
});

// 'connection' and 'validation' are required for 'mail'
// The 'defaults' property within 'validation' is an object type is
// the same shape as recipient and accounts fields.
const mailSchema = z.object({
  connection: mailConnectionSchema,
  validation: z.object({
    defaults: mailValidationSchema.optional(),
  }),
});

const loggingSchema = z.object({
  http_requests: z.boolean().default(true),
});

const i18nSchema = z.object({
  enabled: z.boolean().default(false),
  default_locale: z.string().default('en'),
  fallback_locale: z.record(z.string(), z.union([z.array(z.string()), z.string()])),
  locales: z.array(z.string()).default([]),
  incomplete: z.array(z.string()).default([]),
});

const developmentSchema = z.object({
  enabled: z.boolean().optional(),
  debug: z.boolean().optional(),
  frontend_host: z.string().optional(),
});

const experimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().default(false),
  rotated_secrets: z.array(z.string()).default([]),
  freeze_app: z.boolean().default(false),
});

const configSchema = z.object({
  site: siteSchema,
  storage: storageSchema,
  mail: mailSchema,
  diagnostics: diagnosticsSchema.optional(), // TODO: revisit to confirm "optional" here
  logging: loggingSchema,
  i18n: i18nSchema,
  development: developmentSchema,
  experimental: experimentalSchema,
});

export type StaticConfig = z.infer<typeof configSchema>;

export { configSchema };
