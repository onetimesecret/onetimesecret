// src/schemas/contracts/config/section/experimental.ts

/**
 * Experimental Configuration Schema
 *
 * Maps to the `experimental:` section in config.defaults.yaml — opt-in,
 * not-yet-stable feature flags. Each flag gates a capability that is safe to
 * disable at any time (rollback is a config flip). Flags graduate out of this
 * section once stable.
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults belong in `shapes/config/section/experimental.ts`.
 */

import { z } from 'zod';

/**
 * Experimental feature flags
 *
 * Extension point for opt-in, not-yet-stable flags. Currently empty — the
 * Colonel admin-console cutover flag was retired once the rebuilt console became
 * the sole admin frontend (docs/specs/colonel-ui/50-cutover-hardening.md).
 * Add new flags here (field + type) with their default in `shapes/`.
 */
const experimentalSchema = z.object({});

export { experimentalSchema };
