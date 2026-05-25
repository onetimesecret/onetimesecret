// src/schemas/shapes/config/section/development.ts

/**
 * Development Configuration Shape
 *
 * Adds runtime defaults on top of the type-only development contract.
 * Consumed by the static config schema for `bin/ots config validate` and
 * JSON Schema generation; the contract stays free of `.default()` calls.
 *
 * @see src/schemas/contracts/config/section/development.ts
 */

import { z } from 'zod';

export { developmentSchema } from '@/schemas/contracts/config/section/development';

/**
 * Development mode configuration with defaults applied.
 *
 * - allow_nil_global_secret: Recovery mode for secrets created without
 *   encryption key. Only effective when development.enabled is true; the
 *   config normalization layer forces this to false when development mode
 *   is off.
 */
const developmentShape = z.object({
  enabled: z.boolean().default(false),
  debug: z.boolean().default(false),
  frontend_host: z.string().default('http://localhost:5173'),
  domain_context_enabled: z.boolean().default(false),
  allow_nil_global_secret: z.boolean().default(false),
});

export { developmentShape };
