// src/tests/schemas/shapes/fixtures/organization-membership.fixtures.ts
//
// OrganizationMembership test fixtures using factory pattern.
// All timestamps use round seconds to survive epoch conversion.
//
// Ruby model safe_dump_fields:
//   id (objid), organization_id (org.extid), email (invited_email),
//   role, status, invited_by, invited_at, expires_at, expired, resend_count, token

import type { OrganizationMembershipCanonical } from '@/schemas/contracts/organization-membership';
import {
  toV2WireOrganizationMembership,
  toV3WireOrganizationMembership,
  type V2WireOrganizationMembership,
  type V3WireOrganizationMembership,
} from '../helpers/serializers';

// Re-export for convenience
export type { OrganizationMembershipCanonical } from '@/schemas/contracts/organization-membership';

// -----------------------------------------------------------------------------
// Constants for round-second timestamps
// -----------------------------------------------------------------------------

/** Base timestamp: 2024-01-15T10:00:00.000Z */
const BASE_TIMESTAMP = new Date('2024-01-15T10:00:00.000Z');

/** One week later (for expires_at) */
const ONE_WEEK_LATER = new Date('2024-01-22T10:00:00.000Z');

/** One day earlier */
const ONE_DAY_EARLIER = new Date('2024-01-14T10:00:00.000Z');

// -----------------------------------------------------------------------------
// Role and Status Enums
// -----------------------------------------------------------------------------

/** Valid membership roles */
export const MEMBERSHIP_ROLES = ['owner', 'admin', 'member'] as const;
export type MembershipRole = (typeof MEMBERSHIP_ROLES)[number];

/** Valid membership statuses */
export const MEMBERSHIP_STATUSES = ['active', 'pending', 'declined', 'expired'] as const;
export type MembershipStatus = (typeof MEMBERSHIP_STATUSES)[number];

// -----------------------------------------------------------------------------
// Canonical Factories
// -----------------------------------------------------------------------------

/**
 * Creates a canonical organization membership with sensible defaults.
 * Defaults to an active membership (most common state).
 * All timestamps are round seconds for epoch conversion safety.
 *
 * Note: The canonical schema does not include joined_at (it's tracked via
 * organization.members sorted set in Ruby, not in the membership record itself).
 */
export function createCanonicalOrganizationMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return {
    // Identity - use realistic identifier formats
    id: 'orgmem12ab34cd',
    organization_id: 'on12ab34cd',

    // Role and status
    role: 'member',
    status: 'active',

    // Invitation target
    email: 'member@example.com',

    // Inviter tracking
    invited_by: 'cust12ab34cd',
    invited_at: BASE_TIMESTAMP,

    // Expiration (for pending invites)
    expires_at: null,
    expired: false,

    // Resend tracking
    resend_count: 0,

    // Token (cleared for active, present for pending)
    token: null,

    ...overrides,
  };
}

// -----------------------------------------------------------------------------
// Status Variant Factories
// -----------------------------------------------------------------------------

/**
 * Creates a pending invitation (not yet accepted).
 * Has token, expires_at.
 */
export function createPendingMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createCanonicalOrganizationMembership({
    id: 'orgmem_pend12',
    status: 'pending',
    token: 'abcd1234efgh5678ijkl9012mnop3456qrst7890',
    invited_at: BASE_TIMESTAMP,
    expires_at: ONE_WEEK_LATER,
    expired: false,
    ...overrides,
  });
}

/**
 * Creates an active membership (invitation accepted).
 * No token, no expires_at.
 */
export function createActiveMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createCanonicalOrganizationMembership({
    id: 'orgmem_act123',
    status: 'active',
    token: null,
    expires_at: null,
    expired: false,
    ...overrides,
  });
}

/**
 * Creates a declined membership (invitation rejected).
 * No token, no expires_at.
 */
export function createDeclinedMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createCanonicalOrganizationMembership({
    id: 'orgmem_dec123',
    status: 'declined',
    token: null,
    invited_at: ONE_DAY_EARLIER,
    expires_at: null,
    expired: false,
    ...overrides,
  });
}

/**
 * Creates an expired membership (invitation timed out).
 * Has expired=true, may still have token for reference.
 */
export function createExpiredMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createCanonicalOrganizationMembership({
    id: 'orgmem_exp123',
    status: 'expired',
    token: 'expired_token_still_present_1234567890',
    invited_at: ONE_DAY_EARLIER,
    expires_at: BASE_TIMESTAMP, // Expiration passed
    expired: true,
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Role Variant Factories
// -----------------------------------------------------------------------------

/**
 * Creates an owner membership (highest privilege level).
 * Full access, billing, can delete org.
 */
export function createOwnerMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createActiveMembership({
    id: 'orgmem_own123',
    role: 'owner',
    email: 'owner@example.com',
    ...overrides,
  });
}

/**
 * Creates an admin membership.
 * Can manage members and settings (no billing/delete).
 */
export function createAdminMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createActiveMembership({
    id: 'orgmem_adm123',
    role: 'admin',
    email: 'admin@example.com',
    ...overrides,
  });
}

/**
 * Creates a member membership (basic access).
 * Can use features, view members.
 */
export function createMemberMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createActiveMembership({
    id: 'orgmem_mem123',
    role: 'member',
    email: 'member@example.com',
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Edge Case Factories
// -----------------------------------------------------------------------------

/**
 * Creates a membership with multiple resends.
 */
export function createResentMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createPendingMembership({
    id: 'orgmem_resent1',
    resend_count: 3,
    ...overrides,
  });
}

/**
 * Creates a minimal membership with nullable fields set to null.
 */
export function createMinimalMembership(
  overrides?: Partial<OrganizationMembershipCanonical>
): OrganizationMembershipCanonical {
  return createCanonicalOrganizationMembership({
    id: 'orgmem_min123',
    organization_id: null,
    email: null,
    role: 'member',
    status: 'active',
    invited_by: null,
    invited_at: null,
    expires_at: null,
    expired: false,
    resend_count: 0,
    token: null,
    ...overrides,
  });
}

// -----------------------------------------------------------------------------
// Wire Format Factories (use serializers)
// -----------------------------------------------------------------------------

/**
 * Creates V2 wire format from canonical.
 */
export function createV2WireOrganizationMembership(
  canonical?: OrganizationMembershipCanonical
): V2WireOrganizationMembership {
  return toV2WireOrganizationMembership(
    canonical ?? createCanonicalOrganizationMembership()
  );
}

/**
 * Creates V3 wire format from canonical.
 */
export function createV3WireOrganizationMembership(
  canonical?: OrganizationMembershipCanonical
): V3WireOrganizationMembership {
  return toV3WireOrganizationMembership(
    canonical ?? createCanonicalOrganizationMembership()
  );
}

// -----------------------------------------------------------------------------
// Comparison Functions
// -----------------------------------------------------------------------------

/**
 * Compares two canonical organization memberships for equality.
 * Handles Date comparison by converting to timestamps.
 */
export function compareCanonicalOrganizationMembership(
  a: OrganizationMembershipCanonical,
  b: OrganizationMembershipCanonical
): { equal: boolean; differences: string[] } {
  const differences: string[] = [];

  // String/primitive fields
  const primitiveFields = [
    'id',
    'organization_id',
    'email',
    'role',
    'status',
    'invited_by',
    'expired',
    'resend_count',
    'token',
  ] as const;

  for (const field of primitiveFields) {
    if (a[field] !== b[field]) {
      differences.push(
        `${field}: ${JSON.stringify(a[field])} !== ${JSON.stringify(b[field])}`
      );
    }
  }

  // Date fields (compare as timestamps, handle null)
  const dateFields = ['invited_at', 'expires_at'] as const;

  for (const field of dateFields) {
    const aVal = a[field];
    const bVal = b[field];

    if (aVal === null && bVal === null) {
      continue;
    }
    if (aVal === null || bVal === null) {
      differences.push(`${field}: ${aVal} !== ${bVal}`);
      continue;
    }

    const aTime = aVal instanceof Date ? aVal.getTime() : aVal;
    const bTime = bVal instanceof Date ? bVal.getTime() : bVal;
    if (aTime !== bTime) {
      differences.push(`${field}: ${aTime} !== ${bTime}`);
    }
  }

  return {
    equal: differences.length === 0,
    differences,
  };
}
