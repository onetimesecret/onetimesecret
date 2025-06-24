// src/schemas/models/public.ts
import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

/**
 * Zod schema for SecretOptions
 *
 * @example Validate and parse the data
 *    const parsedSecretOptions: SecretOptions = secretOptionsSchema.parse(receivedSecretOptions);
 *    const parsedAuthSettings: Authentication = authenticationSchema.parse(receivedAuthSettings);
 *
 *    console.log(parsedSecretOptions);
 *       Output:
 *       {
 *         default_ttl: 604800,
 *         ttl_options: [600, 1800, 3600]
 *       }
 *
 */
export const secretOptionsSchema = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * Default: 604800 (7 days in seconds)
   */
  default_ttl: z
    .number()
    .int()
    .positive()
    .default(604800)
    .transform((val) => transforms.fromString.number.parse(val)),

  /**
   * Available TTL options for secret creation (in seconds)
   * These options will be presented to users when they create a new secret
   * Format: Array of integers representing seconds
   * Default: [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    .transform((arr) => arr.map((val) => transforms.fromString.number.parse(val)))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),
});

/**
 * configSchema - Defines the shape of the public configuration.
 *
 * Combined Schema for PublicSettings based on :site in config.schema.yaml
 */
export const configSchema = z
  .object({
    secret_options: secretOptionsSchema,
  })
  .strict();

export type SecretOptions = z.infer<typeof secretOptionsSchema>;
export type PublicSettings = z.infer<typeof configSchema>;
