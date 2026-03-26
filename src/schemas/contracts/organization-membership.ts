// src/schemas/contracts/organization-membership.ts
// @see src/tests/stores/membersStore.spec.ts - Test fixtures for membership schema
//
// Canonical organization membership record schema - field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Organization membership record contracts defining field names and output types.
 *
 * OrganizationMembership is a "through" model that tracks the relationship
 * between Organizations and Customers. It stores rich membership data including
 * roles, invitation status, and audit trails.
 *
 * Key characteristics:
 * - Tracks membership metadata, not the member itself
 * - Supports invitation workflow (pending -> active/declined/expired)
 * - Role hierarchy: owner > admin > member
 *
 * Version-specific shapes in `shapes/v2/organization-membership.ts` and
 * `shapes/v3/organization-membership.ts` extend these with appropriate
 * transforms for each API version.
 *
 * @module contracts/organization-membership
 * @category Contracts
 * @see {@link "shapes/v2/organization-membership"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/organization-membership"} - V3 wire format with native types
 */

import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Membership role enum
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Organization membership role values.
 *
 * Role hierarchy (highest to lowest):
 * - owner: Full access, billing, delete org
 * - admin: Manage members, settings (no billing/delete)
 * - member: Use features, view members
 *
 * @category Contracts
 */
export const membershipRoleValues = ['owner', 'admin', 'member'] as const;

export type MembershipRole = (typeof membershipRoleValues)[number];

/**
 * Membership role enum object for runtime checks.
 *
 * @category Contracts
 * @example
 * ```typescript
 * if (membership.role === MembershipRole.OWNER) {
 *   // Full access granted
 * }
 * ```
 */
export const MembershipRole = {
  OWNER: 'owner',
  ADMIN: 'admin',
  MEMBER: 'member',
} as const;

export const membershipRoleSchema = z.enum(membershipRoleValues);

// ─────────────────────────────────────────────────────────────────────────────
// Membership status enum
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Organization membership status values.
 *
 * Status workflow:
 * - pending: Invitation sent, awaiting acceptance
 * - active: Member has accepted and joined
 * - declined: Member declined the invitation
 * - expired: Invitation expired (7 days default)
 *
 * @category Contracts
 */
export const membershipStatusValues = ['active', 'pending', 'declined', 'expired'] as const;

export type MembershipStatus = (typeof membershipStatusValues)[number];

/**
 * Membership status enum object for runtime checks.
 *
 * @category Contracts
 * @example
 * ```typescript
 * switch (membership.status) {
 *   case MembershipStatus.PENDING:
 *     return 'Invitation sent';
 *   case MembershipStatus.ACTIVE:
 *     return 'Active member';
 *   case MembershipStatus.DECLINED:
 *     return 'Invitation declined';
 *   case MembershipStatus.EXPIRED:
 *     return 'Invitation expired';
 * }
 * ```
 */
export const MembershipStatus = {
  ACTIVE: 'active',
  PENDING: 'pending',
  DECLINED: 'declined',
  EXPIRED: 'expired',
} as const;

export const membershipStatusSchema = z.enum(membershipStatusValues);

/**
 * Type guard for membership status validation.
 *
 * @param status - String to validate
 * @returns True if status is a valid MembershipStatus value
 *
 * @category Contracts
 */
export function isValidMembershipStatus(status: string): status is MembershipStatus {
  return membershipStatusValues.includes(status as MembershipStatus);
}

/**
 * Type guard for membership role validation.
 *
 * @param role - String to validate
 * @returns True if role is a valid MembershipRole value
 *
 * @category Contracts
 */
export function isValidMembershipRole(role: string): role is MembershipRole {
  return membershipRoleValues.includes(role as MembershipRole);
}

// ─────────────────────────────────────────────────────────────────────────────
// Organization membership canonical schema
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Canonical organization membership record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * Field mapping from Ruby safe_dump_fields:
 * - id: objid (internal identifier)
 * - organization_id: org.extid (external identifier for API responses)
 * - email: invited_email (email for pending invites)
 * - role: membership role (owner/admin/member)
 * - status: membership status (active/pending/declined/expired)
 * - invited_by: customer objid who sent the invite
 * - invited_at: timestamp of invitation
 * - expires_at: computed invitation expiration timestamp
 * - expired: computed boolean indicating if invitation has expired
 * - resend_count: number of times invitation was resent
 * - token: secure token for invitation links (null after acceptance)
 *
 * @category Contracts
 * @see {@link "shapes/v2/organization-membership".organizationMembershipSchema} - V2 wire format
 * @see {@link "shapes/v3/organization-membership".organizationMembershipRecord} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const membershipV3 = organizationMembershipCanonical.extend({
 *   invited_at: transforms.fromNumber.toDateNullable,
 *   expires_at: transforms.fromNumber.toDateNullable,
 * });
 *
 * // Derive TypeScript type
 * type OrganizationMembership = z.infer<typeof organizationMembershipCanonical>;
 * ```
 */
export const organizationMembershipCanonical = z.object({
  // ─────────────────────────────────────────────────────────────────────────
  // Identity fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Internal object identifier (objid). */
  id: z.string(),

  /** Organization's external identifier (extid) for API responses. */
  organization_id: z.string().nullable(),

  // ─────────────────────────────────────────────────────────────────────────
  // Role and status
  // ─────────────────────────────────────────────────────────────────────────

  /** Member role in the organization. */
  role: membershipRoleSchema,

  /** Current membership status. */
  status: membershipStatusSchema,

  // ─────────────────────────────────────────────────────────────────────────
  // Invitation fields
  // ─────────────────────────────────────────────────────────────────────────

  /** Email address for pending invites (before account exists). */
  email: z.string().nullable(),

  /** Customer objid who sent the invitation. */
  invited_by: z.string().nullable(),

  /** Timestamp when invitation was sent. */
  invited_at: z.date().nullable(),

  /** Computed expiration timestamp for invitation. */
  expires_at: z.date().nullable(),

  /** Whether the invitation has expired (computed). */
  expired: z.boolean(),

  /** Number of times the invitation was resent. */
  resend_count: z.number(),

  /** Secure token for invitation links (cleared after acceptance). */
  token: z.string().nullable(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for organization membership record. */
export type OrganizationMembershipCanonical = z.infer<typeof organizationMembershipCanonical>;
