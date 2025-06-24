// src/schemas/config/index.ts

/**
 * Static Configuration Schema
 *
 * This schema defines the static configuration that sets up the basic structure
 * and capabilities of the application. It determines what features are available
 * and how different components connect to each other. The configuration is
 * loaded once when the application starts up and remains unchanged until the
 * application is restarted.
 */

import { z } from 'zod/v4';

import { siteSchema } from './section/site';
import { storageSchema } from './section/storage';
import { mailConnectionSchema, mailValidationSchema } from './section/mail';
import { diagnosticsSchema } from './section/diagnostics';

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

export type Config = z.infer<typeof configSchema>;

export { configSchema };
