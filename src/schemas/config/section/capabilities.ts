// src/schemas/config/section/capabilities.ts

/**
 * Capabilities
 *
 * Previously these flags were defined in Onetime::Plan.load_plans! and by
 * plan ID rather than anonymous or authenticated. This means that the domains
 * tab for authenticated users is either enabled or disabled, regardless of
 * the plan.
 *
 */

import { z } from 'zod/v4';
import { ValidKeys as UserTypeKeys } from '../shared/user_types';

const capabilityFlagsSchema = z.object({
  api: z.boolean(),
  email: z.boolean(),
  custom_domains: z.boolean(),
});

// @see Zod v4 note about using enums for record keys:
//  https://zod.dev/api?id=records
const capabilitiesSchema = z.record(UserTypeKeys, capabilityFlagsSchema);

export { capabilitiesSchema };
