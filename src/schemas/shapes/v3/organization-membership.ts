// src/schemas/shapes/v3/organization-membership.ts
//
// V3 wire-format shapes for organization memberships.
// Derives from contracts, adding V3-specific transforms (number -> Date, native types).

import {
  organizationMembershipCanonical,
  membershipRoleSchema,
  membershipStatusSchema,
} from '@/schemas/contracts/organization-membership';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 wire-format overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides for V3 wire format.
 * V3 sends timestamps as Unix epoch numbers (or null); these transform to Date objects.
 */
const v3TimestampOverrides = {
  invited_at: transforms.fromNumber.toDateNullable,
  expires_at: transforms.fromNumber.toDateNullable,
};

// ─────────────────────────────────────────────────────────────────────────────
// V3 organization membership shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 organization membership record.
 *
 * Derives from contract, adds V3 wire-format transforms:
 * - Timestamps: number (Unix epoch seconds) -> Date | null
 * - Boolean fields: native booleans (no string transform needed)
 * - Number fields: native numbers (no string transform needed)
 *
 * V3 is the clean API - native JSON types without string encoding.
 *
 * @example
 * ```typescript
 * const membership = organizationMembershipRecord.parse({
 *   id: 'mem_abc123',
 *   organization_id: 'on1a2b3c4d',
 *   email: 'user@example.com',
 *   role: 'member',
 *   status: 'pending',
 *   invited_by: 'cust_xyz789',
 *   invited_at: 1609459200,
 *   expires_at: 1610064000,
 *   expired: false,
 *   resend_count: 0,
 *   token: 'secure_token_here',
 * });
 *
 * console.log(membership.invited_at instanceof Date); // true
 * console.log(membership.expired); // false (native boolean)
 * console.log(membership.resend_count); // 0 (native number)
 * ```
 */
export const organizationMembershipRecord = organizationMembershipCanonical.extend({
  // Wire-format overrides for timestamps
  ...v3TimestampOverrides,

  // V3 sends native types, but add defaults for optional fields
  organization_id: z.string().nullable().default(null),
  email: z.string().nullable().default(null),
  role: membershipRoleSchema.default('member'),
  status: membershipStatusSchema.default('active'),
  invited_by: z.string().nullable().default(null),
  expired: z.boolean().default(false),
  resend_count: z.number().default(0),
  token: z.string().nullable().default(null),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V3 organization membership record. */
export type OrganizationMembershipRecord = z.infer<typeof organizationMembershipRecord>;
