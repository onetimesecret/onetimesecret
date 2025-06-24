// src/schemas/config/public.ts

// NOTE: THIS IS A WIP

import { z } from 'zod/v4';

import { secretOptionsSchema } from './mutable';

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
