// src/schemas/shapes/config/section/experimental.ts

/**
 * Experimental Configuration Shape
 *
 * Adds runtime defaults on top of the type-only experimental contract.
 * Consumed by the static config schema for `bin/ots config validate` and
 * JSON Schema generation; the contract stays free of `.default()` calls.
 *
 * @see src/schemas/contracts/config/section/experimental.ts
 */

import { experimentalSchema } from '@/schemas/contracts/config/section/experimental';
import { augment } from '@/schemas/utils/augment';

export { experimentalSchema };

const experimentalShape = augment(experimentalSchema, {
  admin_v2: (b) => b.default(false),
});

export { experimentalShape };
