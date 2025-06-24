// src/schemas/config/section/secret_options.ts

/**
 * User Types
 *
 * Previously defined in Onetime::Plan.load_plans!
 */

import { z } from 'zod/v4';

import { ValidKeys as UserTypeKeys } from '../shared/user_types';

const secretOptionBoundariessSchema = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   *
   * @default 604800 (7 days in seconds)
   */
  default_ttl: z.number().int().positive().default(604800),

  /**
   * Available TTL options for secret creation (in seconds)
   *
   * These options will be presented to users when they create a new secret
   * Format: An array of numbers.
   *
   * NOTE: Previously could be nil depending on how the TTL_OPTIONS env var
   * was set. Now as mutable config, it must be set on the correct format.
   *
   * @min 60 - One minute
   * @max 2592000 - 30 days
   * @default [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    // .transform((arr) => arr.map((val) => transforms.fromString.number.parse(val)))
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),

  size: z
    .number()
    .int()
    .positive()
    .min(1)
    .max(10485760) // 10MB
    .default(102400), // 100KB
});

// @see Zod v4 note about using enums for record keys:
//  https://zod.dev/api?id=records
const secretOptionsSchema = z.record(UserTypeKeys, secretOptionBoundariessSchema);

export { secretOptionsSchema };
