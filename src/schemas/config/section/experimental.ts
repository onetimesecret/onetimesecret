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
 *
 * - allow_nil_global_secret: Recovery mode for secrets created without encryption key
 * - rotated_secrets: Previous secret keys for zero-downtime rotation
 *   NOTE: Only works with LegacyEncryptedFields (Secret/Metadata content),
 *   not with Familia's EncryptedFields or other secret systems
 * - csp: Content Security Policy configuration
 */
const experimentalSchema = z.object({
  allow_nil_global_secret: z.boolean().default(false),
  rotated_secrets: z.array(z.string()).default([]),
  csp: cspSchema.optional(),
});

export { experimentalSchema, cspSchema };
