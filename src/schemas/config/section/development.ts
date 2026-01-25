// src/schemas/config/section/development.ts

/**
 * Development Configuration Schema
 *
 * Maps to the `development:` section in config.defaults.yaml
 */

import { z } from 'zod/v4';

/**
 * Development mode configuration
 */
const developmentSchema = z.object({
  enabled: z.boolean().default(false),
  debug: z.boolean().default(false),
  frontend_host: z.string().default('http://localhost:5173'),
});

export { developmentSchema };
