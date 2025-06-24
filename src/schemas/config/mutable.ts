// src/schemas/config/runtime.ts

/**
 * Mutable Configuration Schema
 *
 * This schema defines configuration settings that control how the application
 * behaves and what rules it follows. These settings work within the boundaries
 * established by the static configuration and can be modified while the
 * application is running without requiring a restart.
 *
 * TODO: import { transforms } from '@/schemas/transforms';
 *
 */

import { z } from 'zod/v4';

import { userInterfaceSchema } from './section/ui';
import { featuresSchema } from './section/features';
import { mailValidationSchema } from './section/mail';
import { limitsSchema } from './section/limits';

const apiSchema = z.object({
  enabled: z.boolean().default(true),
});

const secretOptionsSchema = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   *
   * @default 604800 (7 days in seconds)
   */
  default_ttl: z.number().int().positive().default(604800),

  /**
   * Available TTL options for secret creation (in seconds)
   *
   * These options will be presented to users when they create a new secret
   * Format: An array of numbers.
   *
   * NOTE: Previously could be nil depending on how the TTL_OPTIONS env var
   * was set. Now as mutable config, it must be set on the correct format.
   *
   * @min 60 - One minute
   * @max 2592000 - 30 days
   * @default [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    // .transform((arr) => arr.map((val) => transforms.fromString.number.parse(val)))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),
});

// Mutable configuration can define mail validation rules separately for
// recipients and accounts but cannot set (or override) the static defaults.
const mailSchema = z.object({
  validation: z.object({
    recipients: mailValidationSchema.optional(),
    accounts: mailValidationSchema.optional(),
  }),
});

/**
 * configSchema - Defines the shape of the mutable configuration.
 *
 */
const configSchema = z.object({
  ui: userInterfaceSchema.optional(), // Renamed from interface
  api: apiSchema.optional(),
  secret_options: secretOptionsSchema.optional(),
  mail: mailSchema.optional(),
  features: featuresSchema.optional(),
  limits: limitsSchema.optional(),
});

export const mutableSettingsDetailsSchema = configSchema.extend({}); // TODO: Revisit and remove
export type MutableSettingsDetails = z.infer<typeof mutableSettingsDetailsSchema>;

export type Config = z.infer<typeof configSchema>;

export { configSchema, secretOptionsSchema, mailSchema };
