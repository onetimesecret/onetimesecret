// src/schemas/config/user_types.ts

/**
 * User Types
 *
 * Previously these flags were defined in Onetime::Plan.load_plans! and by
 * plan ID rather than anonymous or authenticated. This means that the domains
 * tab for authenticated users is either enabled or disabled, regardless of
 * the plan.
 *
 * NOTE: "User" types is the correct nomenclature vs "Profile" because it's
 * at the user-level that authentication happens. It was less clear when the
 * possible keys were anonymous, basic, identity (which is how they were
 * distinguished in onetime/plan.rb).
 */

import { z } from 'zod/v4';

// @see Zod v4 note on https://zod.dev/api?id=records
const ValidKeys = z.enum(['anonymous', 'authenticated', 'standard', 'enhanced']);

const userTypesSchema = z.object({
  api: z.boolean(),
  email: z.boolean(),
  custom_domains: z.boolean(),
});

export { userTypesSchema, ValidKeys };
