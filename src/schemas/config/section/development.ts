// src/schemas/config/section/development.ts

/**
 * Development Configuration Schema
 *
 * Maps to the `development:` section in config.defaults.yaml
 */

import { z } from 'zod';

/**
 * Development mode configuration
 */
const developmentSchema = z.object({
  enabled: z.boolean().default(false),
  debug: z.boolean().default(false),
  frontend_host: z.string().default('http://localhost:5173'),
  domain_context_enabled: z.boolean().default(false),
  allow_nil_global_secret: z.boolean().optional(),
});

export { developmentSchema };
