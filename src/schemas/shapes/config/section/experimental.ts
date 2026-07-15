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

// No experimental flags are currently defined (the Colonel admin-console
// cutover flag was retired — see docs/specs/colonel-ui/50-cutover-hardening.md).
// The `augment` call is retained as the extension point: add
// `flag: (b) => b.default(...)` here when a new experimental flag lands.
const experimentalShape = augment(experimentalSchema, {});

export { experimentalShape };
