// src/schemas/contracts/config/section/development.ts

/**
 * Development Configuration Schema
 *
 * Maps to the `development:` section in config.defaults.yaml
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints belong in shapes — not here.
 *
 * - allow_nil_global_secret: Recovery mode for secrets created without encryption key.
 *   Only effective when development.enabled is true; the config normalization layer
 *   forces this to false when development mode is off.
 */

import { z } from 'zod';

const developmentSchema = z.object({
  enabled: z.boolean().optional(),
  debug: z.boolean().optional(),
  frontend_host: z.string().optional(),
  domain_context_enabled: z.boolean().optional(),
  allow_nil_global_secret: z.boolean().optional(),
});

export { developmentSchema };
