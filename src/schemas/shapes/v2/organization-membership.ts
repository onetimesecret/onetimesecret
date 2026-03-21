// src/schemas/shapes/v2/organization-membership.ts
//
// V2 wire-format shapes for organization memberships.
// Uses string-to-type transforms for Redis serialization format.

/**
 * V2 organization membership schema with string-to-type transformations.
 *
 * V2 API returns most values as strings (Redis serialization format).
 * This schema transforms wire-format strings to proper TypeScript types.
 *
 * @module shapes/v2/organization-membership
 * @category Shapes
 * @see {@link "contracts/organization-membership"} - Canonical field contract
 * @see {@link "shapes/v3/organization-membership"} - V3 wire format with native types
 */

import {
  membershipRoleSchema,
  membershipStatusSchema,
} from '@/schemas/contracts/organization-membership';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V2 organization membership schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 organization membership schema with unified transformations.
 *
 * Handles V2 wire format where:
 * - Timestamps come as string-encoded Unix timestamps
 * - Booleans come as strings ("true"/"false", "0"/"1")
 * - Numbers come as strings
 *
 * Note: This schema does NOT extend createModelSchema because
 * OrganizationMembership is a "through" model without the standard
 * identifier/created/updated base fields. It uses `id` (objid) instead.
 *
 * @example
 * ```typescript
 * const membership = organizationMembershipSchema.parse({
 *   id: 'mem_abc123',
 *   organization_id: 'on1a2b3c4d',
 *   email: 'user@example.com',
 *   role: 'member',
 *   status: 'pending',
 *   invited_by: 'cust_xyz789',
 *   invited_at: '1609459200',
 *   expires_at: '1610064000',
 *   expired: 'false',
 *   resend_count: '0',
 *   token: 'secure_token_here',
 * });
 *
 * console.log(membership.invited_at instanceof Date); // true
 * console.log(membership.expired); // false (boolean)
 * console.log(membership.resend_count); // 0 (number)
 * ```
 */
export const organizationMembershipSchema = z
  .object({
    // Identity
    id: z.string(),
    organization_id: z.string().nullable().default(null),

    // Role and status (enums, no transform needed)
    role: membershipRoleSchema.default('member'),
    status: membershipStatusSchema.default('active'),

    // Invitation fields
    email: z.string().nullable().default(null),
    invited_by: z.string().nullable().default(null),

    // Timestamps (V2 sends as strings)
    invited_at: transforms.fromString.dateNullable.default(null),
    expires_at: transforms.fromString.dateNullable.default(null),

    // Boolean (V2 sends as string)
    expired: transforms.fromString.boolean.default(false),

    // Number (V2 sends as string)
    resend_count: transforms.fromString.number.default(0),

    // Token (nullable string)
    token: z.string().nullable().default(null),
  })
  .strict();

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for V2 organization membership. */
export type OrganizationMembership = z.infer<typeof organizationMembershipSchema>;
