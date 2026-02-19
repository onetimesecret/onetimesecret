// src/schemas/config/section/secret_options.ts

/**
 * Secret Options Configuration Schema
 *
 * Defines TTL and size limits for different user types.
 * Previously defined in Onetime::Plan.load_plans!
 */

import { z } from 'zod';
import { ValidKeys as UserTypeKeys } from '../shared/user_types';

/**
 * Secret option boundaries for a user type
 */
const secretOptionBoundariesSchema = z.object({
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * @default 604800 (7 days)
   */
  default_ttl: z.number().int().positive().nullable().default(604800),

  /**
   * Available TTL options for secret creation (in seconds)
   * @min 60 - One minute
   * @max 2592000 - 30 days
   * @default [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]
   */
  ttl_options: z
    .array(z.number().int().positive().min(60).max(2592000))
    .nullable()
    .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),

  /**
   * Maximum secret size in bytes
   * @max 10485760 (10MB)
   * @default 102400 (100KB)
   */
  size: z
    .number()
    .int()
    .positive()
    .min(1)
    .max(10485760)
    .nullable()
    .default(102400),
});

/**
 * Secret options schema - maps user types to their boundaries
 *
 * @see Zod v4 note about using enums for record keys:
 *  https://zod.dev/api?id=records
 */
const secretOptionsSchema = z.record(UserTypeKeys, secretOptionBoundariesSchema);

export { secretOptionsSchema, secretOptionBoundariesSchema };
