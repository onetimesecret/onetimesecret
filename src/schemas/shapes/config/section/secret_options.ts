// src/schemas/shapes/config/section/secret_options.ts

/**
 * Secret Options Configuration Shape
 *
 * Adds runtime defaults and TTL/size bounds on top of the type-only
 * secret_options contract — these were the per-user-type boundaries
 * previously defined in Onetime::Plan.load_plans!.
 *
 * The contract's `secretOptionsSchema` is a `z.record(UserTypeKeys, ...)`
 * rather than a `ZodObject`, so the per-user-type augmentation runs on
 * `secretOptionBoundariesSchema` (the record's value schema) and the
 * shape rewraps it with `z.record(...)` afterward.
 *
 * @see src/schemas/contracts/config/section/secret_options.ts
 */

import { z } from 'zod';
import { ValidKeys as UserTypeKeys } from '@/schemas/contracts/config/shared/user_types';
import {
  secretOptionsSchema,
  secretOptionBoundariesSchema,
} from '@/schemas/contracts/config/section/secret_options';
import { augment } from '@/schemas/utils/augment';

export { secretOptionsSchema, secretOptionBoundariesSchema };

const secretOptionBoundariesShape = augment(secretOptionBoundariesSchema, {
  /**
   * Default Time-To-Live (TTL) for secrets in seconds
   * @default 604800 (7 days)
   */
  default_ttl: (n) => n.int().positive().nullable().default(604800),

  /**
   * Available TTL options for secret creation (in seconds).
   * @min 60 - One minute
   * @max 2592000 - 30 days
   * @default [300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]
   */
  ttl_options: () =>
    z
      .array(z.number().int().positive().min(60).max(2592000))
      .nullable()
      .default([300, 1800, 3600, 14400, 43200, 86400, 259200, 604800, 1209600, 2592000]),

  /**
   * Maximum secret size in bytes
   * @max 10485760 (10MB)
   * @default 102400 (100KB)
   */
  size: (n) => n.int().positive().min(1).max(10485760).nullable().default(102400),
});

const secretOptionsShape = z.record(UserTypeKeys, secretOptionBoundariesShape);

export { secretOptionsShape, secretOptionBoundariesShape };
