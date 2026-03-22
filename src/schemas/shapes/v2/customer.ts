// src/schemas/shapes/v2/customer.ts
//
// V2 wire-format shapes for customers.
// Derives from contracts, adding V2-specific string transforms.
//
// V2 API sends data as Redis-serialized strings; these transforms convert
// to the correct output types.

import { customerRoleSchema } from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { withFeatureFlags } from '@/schemas/utils/feature_flags';
import { z } from 'zod';

import { createModelSchema } from './base';

// ─────────────────────────────────────────────────────────────────────────────
// V2 role re-exports (canonical values from contracts)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 customer role values.
 *
 * Re-exports canonical role values from contracts (no V2-specific aliases).
 */
export {
  customerRoleValues,
  customerRoleSchema,
  CustomerRole,
  isValidCustomerRole,
} from '@/schemas/contracts';

// ─────────────────────────────────────────────────────────────────────────────
// V2 customer schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 customer schema with unified transformations.
 *
 * Transforms string-encoded values from V2 API/Redis to typed values.
 * Uses createModelSchema to add identifier, created, updated from base.
 */
export const customerSchema = withFeatureFlags(
  createModelSchema({
    // Core fields
    objid: z.string(),
    extid: z.string(),

    role: customerRoleSchema,
    email: z.email(),

    // Boolean fields from API
    verified: transforms.fromString.boolean,
    active: transforms.fromString.boolean,
    contributor: transforms.fromString.boolean.optional(),

    // Counter fields from API with default values
    secrets_created: transforms.fromString.number.default(0),
    secrets_burned: transforms.fromString.number.default(0),
    secrets_shared: transforms.fromString.number.default(0),
    emails_sent: transforms.fromString.number.default(0),

    // Date fields
    last_login: transforms.fromString.dateNullable,

    // Optional fields
    locale: z.string().nullable(),

    // Notification preferences
    notify_on_reveal: transforms.fromString.boolean.default(false),
  }).strict()
);

// Update the type to explicitly use Date for timestamps
export type Customer = Omit<z.infer<typeof customerSchema>, 'created' | 'updated'> & {
  created: Date;
  updated: Date;
};
