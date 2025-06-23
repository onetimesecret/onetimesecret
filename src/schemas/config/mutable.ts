// src/schemas/config/runtime.ts

import { z } from 'zod/v4';
import { nullableString } from './shared/primitives';

import { userInterfaceSchema } from './section/ui';
import { featuresSchema } from './section/features';
import { mailValidationSchema } from './section/mail';
import { limitsSchema } from './section/limits';

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

// Mutable configuration can define mail validation rules separately for
// recipients and accounts but cannot set (or override) the static defaults.
const mutableMailSchema = z.object({
  validation: z.object({
    recipients: mailValidationSchema.optional(),
    accounts: mailValidationSchema.optional(),
  }),
});

const configSchema = z.object({
  ui: userInterfaceSchema.optional(), // Renamed from interface
  api: apiSchema.optional(),
  secret_options: sectionSecretOptionsSchema.optional(),
  mail: mutableMailSchema.optional(),
  features: featuresSchema.optional(),
  limits: limitsSchema.optional(),
});

export const mutableSettingsDetailsSchema = configSchema.extend({}); // TODO: Revisit and remove
export type MutableSettingsDetails = z.infer<typeof mutableSettingsDetailsSchema>;

export type Config = z.infer<typeof configSchema>;

export { configSchema };
