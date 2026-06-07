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

import { developmentSchema } from '@/schemas/contracts/config/section/development';
import { augment } from '@/schemas/utils/augment';

export { developmentSchema };

const developmentShape = augment(developmentSchema, {
  enabled: (b) => b.default(false),
  debug: (b) => b.default(false),
  frontend_host: (s) => s.default('http://localhost:5173'),
  domain_context_enabled: (b) => b.default(false),
  allow_nil_global_secret: (b) => b.default(false),
});

export { developmentShape };
