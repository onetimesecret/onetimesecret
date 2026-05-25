// src/schemas/contracts/config/section/secret_options.ts

/**
 * Secret Options Configuration Schema
 *
 * Defines TTL and size limits for different user types.
 * Previously defined in Onetime::Plan.load_plans!
 *
 * Per contracts convention, this schema describes field names and types only.
 * Defaults and value constraints (TTL bounds, size limits) belong in shapes —
 * not here.
 */

import { z } from 'zod';
import { ValidKeys as UserTypeKeys } from '../shared/user_types';

/**
 * Secret option boundaries for a user type
 */
const secretOptionBoundariesSchema = z.object({
  /** Default Time-To-Live (TTL) for secrets in seconds. */
  default_ttl: z.number().nullable().optional(),

  /** Available TTL options for secret creation (in seconds). */
  ttl_options: z.array(z.number()).nullable().optional(),

  /** Maximum secret size in bytes. */
  size: z.number().nullable().optional(),
});

/**
 * Secret options schema - maps user types to their boundaries
 *
 * @see Zod v4 note about using enums for record keys:
 *  https://zod.dev/api?id=records
 */
const secretOptionsSchema = z.record(UserTypeKeys, secretOptionBoundariesSchema);

export { secretOptionsSchema, secretOptionBoundariesSchema };
