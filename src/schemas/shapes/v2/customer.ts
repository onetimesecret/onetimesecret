// src/schemas/shapes/v2/customer.ts
//
// V2 wire-format shapes for customers.
// Derives from contracts, adding V2-specific string transforms.
//
// V2 API sends data as Redis-serialized strings; these transforms convert
// to the correct output types.
//
// Architecture: contract → shapes → api responses
// - customerCanonical defines field names and output types
// - This V2 shape applies string transforms for Redis wire format

import { customerCanonical, customerRoleSchema } from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { withFeatureFlags } from '@/schemas/utils/feature_flags';

// ─────────────────────────────────────────────────────────────────────────────
// V2 role re-exports (canonical values from contracts)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 customer role values.
 *
 * Re-exports canonical role values from contracts (no V2-specific aliases).
 */
export {
  CustomerRole,
  customerRoleSchema,
  customerRoleValues,
  isValidCustomerRole,
} from '@/schemas/contracts';

// ─────────────────────────────────────────────────────────────────────────────
// V2 wire-format overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 sends timestamps as string-encoded Unix timestamps.
 * These transform to Date objects.
 */
const v2TimestampOverrides = {
  created: transforms.fromString.date,
  updated: transforms.fromString.date,
  last_login: transforms.fromString.dateNullable,
};

/**
 * V2 sends booleans as strings ('true'/'false').
 * These transform to native booleans.
 */
const v2BooleanOverrides = {
  verified: transforms.fromString.boolean,
  active: transforms.fromString.boolean,
  contributor: transforms.fromString.boolean.optional(),
  notify_on_reveal: transforms.fromString.boolean.default(false),
};

/**
 * V2 sends counters as strings.
 * These transform to numbers with defaults.
 */
const v2CounterOverrides = {
  secrets_created: transforms.fromString.number.default(0),
  secrets_burned: transforms.fromString.number.default(0),
  secrets_shared: transforms.fromString.number.default(0),
  emails_sent: transforms.fromString.number.default(0),
};

// ─────────────────────────────────────────────────────────────────────────────
// V2 customer schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 customer schema with unified transformations.
 *
 * Derives from customerCanonical contract, applies V2 wire-format transforms:
 * - Timestamps: string (Unix epoch) -> Date
 * - Booleans: string ('true'/'false') -> boolean
 * - Counters: string -> number
 *
 * V2 uses Redis serialization where all values are strings.
 *
 * @example
 * ```typescript
 * const customer = customerSchema.parse({
 *   identifier: 'cust123',
 *   objid: '01234567-89ab-cdef-0123-456789abcdef',
 *   extid: 'cu1a2b3c4d',
 *   email: 'alice@example.com',
 *   role: 'customer',
 *   verified: 'true',
 *   active: 'true',
 *   secrets_created: '5',
 *   created: '1609459200',
 *   updated: '1609545600',
 * });
 *
 * console.log(customer.verified); // true (boolean)
 * console.log(customer.created instanceof Date); // true
 * ```
 */
export const customerSchema = withFeatureFlags(
  customerCanonical
    .extend({
      // V2 wire-format overrides
      ...v2TimestampOverrides,
      ...v2BooleanOverrides,
      ...v2CounterOverrides,

      // Role uses shared schema (no transform needed)
      role: customerRoleSchema,
    })
    .strict()
);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

import { z } from 'zod';

/** TypeScript type for V2 customer record. */
export type Customer = z.infer<typeof customerSchema>;
