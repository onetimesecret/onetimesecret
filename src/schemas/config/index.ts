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

const apiSchema = z.object({
  enabled: z.boolean().default(true),
});

const sectionSecretOptionsSchema = z.object({
  // Can be nil from ENV
  default_ttl: z.number().nullable().optional(),
  ttl_options: z
    .union([z.string(), z.array(z.number())])
    .nullable()
    .optional(), // Can be nil from ENV
});

export const mutableSettingsSchema = z.object({
  user_interface: userInterfaceSchema.optional(), // Renamed from interface
  api: apiSchema.optional(),
  secret_options: sectionSecretOptionsSchema.optional(),
  features: sectionFeaturesSchema.optional(),
  limits: sectionLimitsSchema.optional(),
  mail: mutableMailSchema.optional(), // Updated mail schema
});

export const mutableSettingsDetailsSchema = mutableSettingsSchema.extend({});
export type MutableSettingsDetails = z.infer<typeof mutableSettingsDetailsSchema>;

const sectionLoggingSchema = z.object({
  http_requests: z.boolean().default(true),
});

const sectionDevelopmentSchema = z.object({
  enabled: z.boolean().optional(),
  debug: z.boolean().optional(),
  frontend_host: z.string().optional(),
});

const sectionExperimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().default(false),
  rotated_secrets: z.array(z.string()).default([]),
  freeze_app: z.boolean().default(false),
});

export const staticConfigSchema = z.object({
  site: sectionSiteSchema,
  storage: sectionStorageSchema, // storage itself gets a default empty object
  mail: staticMailSchema,
  logging: sectionLoggingSchema,
  diagnostics: sectionDiagnosticsSchema.optional(),
  i18n: sectionI18nSchema,
  development: sectionDevelopmentSchema,
  experimental: sectionExperimentalSchema,
});

export type StaticConfig = z.infer<typeof staticConfigSchema>;
