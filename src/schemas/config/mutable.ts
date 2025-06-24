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
import { secretOptionsSchema, ValidKeys as SecretOptionsKeys } from './section/secret_options';

const apiSchema = z.object({
  enabled: z.boolean().default(true),
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
  secret_options: z.record(SecretOptionsKeys, secretOptionsSchema),
  mail: mailSchema.optional(),
  features: featuresSchema.optional(),
  limits: limitsSchema.optional(),
});

export const mutableSettingsDetailsSchema = configSchema.extend({}); // TODO: Revisit and remove
export type MutableSettingsDetails = z.infer<typeof mutableSettingsDetailsSchema>;

export type Config = z.infer<typeof configSchema>;

export { configSchema, secretOptionsSchema, mailSchema };
