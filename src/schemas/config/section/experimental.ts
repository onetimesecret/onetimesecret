// src/schemas/config/section/experimental.ts

/**
 * Experimental Configuration Schema
 *
 * Maps to the `experimental:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';

/**
 * Content Security Policy configuration
 */
const cspSchema = z.object({
  enabled: z.boolean().default(false),
});

/**
 * Experimental features configuration
 */
const experimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().default(false),
  rotated_secrets: z.array(z.string()).default([]),
  freeze_app: z.boolean().default(false),
  csp: cspSchema.optional(),
});

export { experimentalSchema, cspSchema };
