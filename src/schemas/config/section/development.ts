// src/schemas/config/section/development.ts

/**
 * Development Configuration Schema
 *
 * Maps to the `development:` section in config.defaults.yaml
 */

import { z } from 'zod';

/**
 * Development mode configuration
 *
 * - allow_nil_global_secret: Recovery mode for secrets created without encryption key.
 *   Only effective when development.enabled is true; the config normalization layer
 *   forces this to false when development mode is off.
 */
const developmentSchema = z.object({
  enabled: z.boolean().default(false),
  debug: z.boolean().default(false),
  frontend_host: z.string().default('http://localhost:5173'),
  domain_context_enabled: z.boolean().default(false),
  allow_nil_global_secret: z.boolean().default(false),
});

export { developmentSchema };
