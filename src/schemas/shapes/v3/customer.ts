// src/schemas/shapes/v3/customer.ts
//
// V3 wire-format shapes for customers.
// Derives from contracts, adding V3-specific transforms (number -> Date, native types).

import {
  customerCanonical,
  customerRoleSchema,
  featureFlagsSchema,
} from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 wire-format overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides for V3 wire format.
 * V3 sends timestamps as Unix epoch numbers; these transform to Date objects.
 */
const v3TimestampOverrides = {
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  last_login: transforms.fromNumber.toDateNullish,
};

/**
 * Feature flags transform for V3 wire format.
 *
 * V3 API may send feature flags as boolean, number (0/1), or string values.
 * This transform normalizes all values to booleans.
 */
const v3FeatureFlagsOverride = {
  feature_flags: z
    .record(z.string(), z.union([z.boolean(), z.number(), z.string()]))
    .transform((val): z.infer<typeof featureFlagsSchema> => {
      const result: Record<string, boolean> = {};
      for (const [key, value] of Object.entries(val)) {
        if (typeof value === 'boolean') {
          result[key] = value;
        } else if (typeof value === 'number') {
          result[key] = value !== 0;
        } else {
          result[key] = value === 'true' || value === '1';
        }
      }
      return result;
    })
    .default({}),
};

// ─────────────────────────────────────────────────────────────────────────────
// V3 customer shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 customer record.
 *
 * Derives from contract, adds V3 wire-format transforms:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Feature flags: mixed types -> boolean record
 * - Counter fields: numbers with default 0
 * - Boolean fields: native booleans
 *
 * V3 is the clean API - native JSON types without string encoding.
 *
 * @example
 * ```typescript
 * const customer = customerRecord.parse({
 *   identifier: 'cust123',
 *   objid: '01234567-89ab-cdef-0123-456789abcdef',
 *   extid: 'ur1a2b3c4d',
 *   email: 'user@example.com',
 *   role: 'customer',
 *   verified: true,
 *   active: true,
 *   secrets_created: 5,
 *   secrets_burned: 1,
 *   secrets_shared: 4,
 *   emails_sent: 3,
 *   last_login: 1609459200,
 *   created: 1609372800,
 *   updated: 1609459200,
 *   locale: 'en',
 *   notify_on_reveal: false,
 *   feature_flags: { allow_public_homepage: true },
 * });
 *
 * console.log(customer.created instanceof Date); // true
 * console.log(customer.last_login instanceof Date); // true
 * ```
 */
export const customerRecord = customerCanonical.extend({
  // Wire-format overrides
  ...v3TimestampOverrides,
  ...v3FeatureFlagsOverride,

  // Role enum (re-declare for explicit wire format)
  role: customerRoleSchema,

  // Counter fields with defaults (V3 sends native numbers)
  secrets_created: z.number().default(0),
  secrets_burned: z.number().default(0),
  secrets_shared: z.number().default(0),
  emails_sent: z.number().default(0),

  // Boolean fields (V3 sends native booleans)
  verified: z.boolean(),
  active: z.boolean(),
  contributor: z.boolean().optional(),
  notify_on_reveal: z.boolean().default(false),

  // Optional locale
  locale: z.string().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 customer record. */
export type CustomerRecord = z.infer<typeof customerRecord>;
