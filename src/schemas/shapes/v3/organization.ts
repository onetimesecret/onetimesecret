// src/schemas/shapes/v3/organization.ts
//
// V3 wire-format shapes for organizations.
// Derives from contracts, adding V3-specific transforms (number -> Date, native types).

import { organizationCanonical } from '@/schemas/contracts';
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
};

// ─────────────────────────────────────────────────────────────────────────────
// V3 organization shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 organization record.
 *
 * Derives from contract, adds V3 wire-format transforms:
 * - Timestamps: number (Unix epoch seconds) -> Date
 * - Boolean fields: native booleans (no string transform needed)
 * - String fields: native strings
 *
 * V3 is the clean API - native JSON types without string encoding.
 *
 * @example
 * ```typescript
 * const org = organizationRecord.parse({
 *   identifier: 'org123',
 *   objid: '01234567-89ab-cdef-0123-456789abcdef',
 *   extid: 'on1a2b3c4d',
 *   display_name: 'Acme Corp',
 *   description: 'A great company',
 *   owner_id: 'cust456',
 *   contact_email: 'billing@acme.com',
 *   is_default: false,
 *   planid: 'pro',
 *   created: 1609372800,
 *   updated: 1609459200,
 * });
 *
 * console.log(org.created instanceof Date); // true
 * console.log(org.is_default); // false (native boolean)
 * ```
 */
export const organizationRecord = organizationCanonical.extend({
  // Wire-format overrides
  ...v3TimestampOverrides,

  // V3 sends native types, but add defaults for optional fields
  description: z.string().nullable().default(null),
  contact_email: z.string().nullable().default(null),
  is_default: z.boolean().default(false),
  planid: z.string().default('free'),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 organization record. */
export type OrganizationRecord = z.infer<typeof organizationRecord>;
