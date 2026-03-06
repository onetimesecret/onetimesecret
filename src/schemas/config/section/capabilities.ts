// src/schemas/config/section/capabilities.ts

/**
 * Capabilities Configuration Schema
 *
 * Defines feature flags for different user types.
 * Previously these flags were defined in Onetime::Plan.load_plans!
 */

import { z } from 'zod';
import { ValidKeys as UserTypeKeys } from '../shared/user_types';

/**
 * Capability flags for a user type
 */
const capabilityFlagsSchema = z.object({
  api: z.boolean(),
  email: z.boolean(),
  custom_domains: z.boolean(),
});

/**
 * Capabilities schema - maps user types to their capability flags
 *
 * @see Zod v4 note about using enums for record keys:
 *  https://zod.dev/api?id=records
 */
const capabilitiesSchema = z.record(UserTypeKeys, capabilityFlagsSchema);

export { capabilitiesSchema, capabilityFlagsSchema };
