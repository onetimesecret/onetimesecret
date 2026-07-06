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
 * - admin_v2: serve the rebuilt Colonel admin console (its own isolated
 *   `admin.ts` bundle + admin shell) at /colonel. When false, the legacy
 *   colonel SPA renders unchanged. See docs/specs/colonel-ui/.
 */
const experimentalSchema = z.object({
  admin_v2: z.boolean().optional(),
});

export { experimentalSchema };
