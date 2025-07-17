// src/schemas/config/shared/user_types.ts

/**
 * User Types
 *
 * @see capabilities.ts, secret_options.ts
 *
 * NOTE: "User" types is the correct nomenclature vs "Profile" because it's
 * at the user-level that authentication happens. It was less clear when the
 * possible keys were anonymous, basic, identity (which is how they were
 * distinguished in onetime/plan.rb).
 */

import { z } from 'zod/v4';

const ValidKeys = z.enum(['anonymous', 'authenticated', 'standard', 'enhanced']);

export { ValidKeys };
