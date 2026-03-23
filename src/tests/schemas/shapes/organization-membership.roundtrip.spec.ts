// src/tests/schemas/shapes/organization-membership.roundtrip.spec.ts
//
// Round-trip tests for organization membership schemas (V2 and V3).
// Verifies: canonical -> wire -> parse -> canonical preserves data.
//
// Purpose:
//   - Verify serializer functions match schema expectations
//   - Catch type mismatches between canonical and wire formats
//   - Document expected transform behavior
//
// Pattern:
//   1. Create canonical membership
//   2. Convert to wire format (V2 or V3)
//   3. Parse wire format with schema
//   4. Compare parsed result to original canonical

import { describe, it, expect } from 'vitest';
import { organizationMembershipSchema as v2MembershipSchema } from '@/schemas/shapes/v2/organization-membership';
import { organizationMembershipRecord as v3MembershipSchema } from '@/schemas/shapes/v3/organization-membership';
import {
  createCanonicalOrganizationMembership,
  createPendingMembership,
  createActiveMembership,
  createDeclinedMembership,
  createExpiredMembership,
  createOwnerMembership,
  createAdminMembership,
  createMemberMembership,
  createMinimalMembership,
  createResentMembership,
  createV2WireOrganizationMembership,
  createV3WireOrganizationMembership,
  compareCanonicalOrganizationMembership,
  type OrganizationMembershipCanonical,
} from './fixtures/organization-membership.fixtures';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Asserts that two dates are equal by timestamp.
 * Handles null comparison.
 */
function expectDatesEqual(
  actual: Date | null,
  expected: Date | null,
  fieldName: string
) {
  if (expected === null) {
    expect(actual, `${fieldName} should be null`).toBeNull();
  } else {
    expect(actual, `${fieldName} should be a Date`).toBeInstanceOf(Date);
    expect(actual!.getTime(), `${fieldName} timestamp mismatch`).toBe(
      expected.getTime()
    );
  }
}

// -----------------------------------------------------------------------------
// V2 Organization Membership Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V2 Organization Membership Round-Trip', () => {
  describe('organizationMembershipSchema', () => {
    it('round-trips a standard active membership', () => {
      const canonical = createCanonicalOrganizationMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      // Verify all fields match
      expect(parsed.id).toBe(canonical.id);
      expect(parsed.organization_id).toBe(canonical.organization_id);
      expect(parsed.email).toBe(canonical.email);
      expect(parsed.role).toBe(canonical.role);
      expect(parsed.status).toBe(canonical.status);
      expect(parsed.invited_by).toBe(canonical.invited_by);
      expect(parsed.expired).toBe(canonical.expired);
      expect(parsed.resend_count).toBe(canonical.resend_count);
      expect(parsed.token).toBe(canonical.token);

      // Timestamps (compare as milliseconds)
      expectDatesEqual(parsed.invited_at, canonical.invited_at, 'invited_at');
      expectDatesEqual(parsed.expires_at, canonical.expires_at, 'expires_at');
    });

    it('round-trips a pending invitation', () => {
      const canonical = createPendingMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.status).toBe('pending');
      expect(parsed.token).toBe(canonical.token);
      expectDatesEqual(parsed.expires_at, canonical.expires_at, 'expires_at');
      expect(parsed.expired).toBe(false);
    });

    it('round-trips an active membership', () => {
      const canonical = createActiveMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.status).toBe('active');
      expect(parsed.token).toBeNull();
      expect(parsed.expires_at).toBeNull();
    });

    it('round-trips a declined membership', () => {
      const canonical = createDeclinedMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.status).toBe('declined');
      expect(parsed.token).toBeNull();
    });

    it('round-trips an expired membership', () => {
      const canonical = createExpiredMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.status).toBe('expired');
      expect(parsed.expired).toBe(true);
      expect(parsed.token).toBe(canonical.token);
    });

    it('round-trips minimal membership (null fields)', () => {
      const canonical = createMinimalMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.organization_id).toBeNull();
      expect(parsed.email).toBeNull();
      expect(parsed.invited_by).toBeNull();
      expect(parsed.invited_at).toBeNull();
      expect(parsed.expires_at).toBeNull();
      expect(parsed.token).toBeNull();
    });

    it('uses compareCanonicalOrganizationMembership for full equality check', () => {
      const canonical = createCanonicalOrganizationMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      const comparison = compareCanonicalOrganizationMembership(
        canonical,
        parsed as OrganizationMembershipCanonical
      );

      expect(comparison.equal).toBe(true);
      expect(comparison.differences).toEqual([]);
    });
  });

  describe('role variations', () => {
    it('round-trips owner membership', () => {
      const canonical = createOwnerMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.role).toBe('owner');
    });

    it('round-trips admin membership', () => {
      const canonical = createAdminMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.role).toBe('admin');
    });

    it('round-trips member membership', () => {
      const canonical = createMemberMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.role).toBe('member');
    });

    it.each(['owner', 'admin', 'member'] as const)(
      'round-trips membership with role=%s',
      (role) => {
        const canonical = createCanonicalOrganizationMembership({ role });
        const v2Wire = createV2WireOrganizationMembership(canonical);
        const parsed = v2MembershipSchema.parse(v2Wire);

        expect(parsed.role).toBe(role);
      }
    );
  });

  describe('status variations', () => {
    it.each(['active', 'pending', 'declined', 'expired'] as const)(
      'round-trips membership with status=%s',
      (status) => {
        const canonical = createCanonicalOrganizationMembership({ status });
        const v2Wire = createV2WireOrganizationMembership(canonical);
        const parsed = v2MembershipSchema.parse(v2Wire);

        expect(parsed.status).toBe(status);
      }
    );
  });

  describe('edge cases', () => {
    it('handles membership with multiple resends', () => {
      const canonical = createResentMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.resend_count).toBe(3);
    });

    it('handles special characters in email', () => {
      const canonical = createCanonicalOrganizationMembership({
        email: 'test+alias@example.com',
      });
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.email).toBe('test+alias@example.com');
    });

    it('handles long token values', () => {
      const longToken = 'a'.repeat(100);
      const canonical = createPendingMembership({
        token: longToken,
      });
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.token).toBe(longToken);
    });

    it('handles zero resend_count', () => {
      const canonical = createCanonicalOrganizationMembership({
        resend_count: 0,
      });
      const v2Wire = createV2WireOrganizationMembership(canonical);
      const parsed = v2MembershipSchema.parse(v2Wire);

      expect(parsed.resend_count).toBe(0);
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Organization Membership Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V3 Organization Membership Round-Trip', () => {
  describe('organizationMembershipRecord', () => {
    it('round-trips a standard active membership', () => {
      const canonical = createCanonicalOrganizationMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      // Verify all fields match
      expect(parsed.id).toBe(canonical.id);
      expect(parsed.organization_id).toBe(canonical.organization_id);
      expect(parsed.email).toBe(canonical.email);
      expect(parsed.role).toBe(canonical.role);
      expect(parsed.status).toBe(canonical.status);
      expect(parsed.invited_by).toBe(canonical.invited_by);
      expect(parsed.expired).toBe(canonical.expired);
      expect(parsed.resend_count).toBe(canonical.resend_count);
      expect(parsed.token).toBe(canonical.token);

      // Timestamps (compare as milliseconds)
      expectDatesEqual(parsed.invited_at, canonical.invited_at, 'invited_at');
      expectDatesEqual(parsed.expires_at, canonical.expires_at, 'expires_at');
    });

    it('round-trips a pending invitation', () => {
      const canonical = createPendingMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.status).toBe('pending');
      expect(parsed.token).toBe(canonical.token);
      expectDatesEqual(parsed.expires_at, canonical.expires_at, 'expires_at');
      expect(parsed.expired).toBe(false);
    });

    it('round-trips an active membership', () => {
      const canonical = createActiveMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.status).toBe('active');
      expect(parsed.token).toBeNull();
      expect(parsed.expires_at).toBeNull();
    });

    it('round-trips a declined membership', () => {
      const canonical = createDeclinedMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.status).toBe('declined');
      expect(parsed.token).toBeNull();
    });

    it('round-trips an expired membership', () => {
      const canonical = createExpiredMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.status).toBe('expired');
      expect(parsed.expired).toBe(true);
    });

    it('round-trips minimal membership (null fields)', () => {
      const canonical = createMinimalMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.organization_id).toBeNull();
      expect(parsed.email).toBeNull();
      expect(parsed.invited_by).toBeNull();
      expect(parsed.invited_at).toBeNull();
      expect(parsed.expires_at).toBeNull();
      expect(parsed.token).toBeNull();
    });

    it('uses compareCanonicalOrganizationMembership for full equality check', () => {
      const canonical = createCanonicalOrganizationMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      const comparison = compareCanonicalOrganizationMembership(
        canonical,
        parsed as OrganizationMembershipCanonical
      );

      expect(comparison.equal).toBe(true);
      expect(comparison.differences).toEqual([]);
    });
  });

  describe('V3 wire format types', () => {
    it('sends timestamps as numbers', () => {
      const canonical = createPendingMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(typeof v3Wire.invited_at).toBe('number');
      expect(typeof v3Wire.expires_at).toBe('number');
    });

    it('sends booleans as native booleans', () => {
      const canonical = createExpiredMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(typeof v3Wire.expired).toBe('boolean');
      expect(v3Wire.expired).toBe(true);
    });

    it('sends numbers as native numbers', () => {
      const canonical = createResentMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(typeof v3Wire.resend_count).toBe('number');
      expect(v3Wire.resend_count).toBe(3);
    });
  });

  describe('role variations', () => {
    it.each(['owner', 'admin', 'member'] as const)(
      'round-trips membership with role=%s',
      (role) => {
        const canonical = createCanonicalOrganizationMembership({ role });
        const v3Wire = createV3WireOrganizationMembership(canonical);
        const parsed = v3MembershipSchema.parse(v3Wire);

        expect(parsed.role).toBe(role);
      }
    );
  });

  describe('status variations', () => {
    it.each(['active', 'pending', 'declined', 'expired'] as const)(
      'round-trips membership with status=%s',
      (status) => {
        const canonical = createCanonicalOrganizationMembership({ status });
        const v3Wire = createV3WireOrganizationMembership(canonical);
        const parsed = v3MembershipSchema.parse(v3Wire);

        expect(parsed.status).toBe(status);
      }
    );
  });

  describe('timestamp edge cases', () => {
    it('handles null invited_at', () => {
      const canonical = createMinimalMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.invited_at).toBeNull();
    });

    it('handles null expires_at', () => {
      const canonical = createActiveMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.expires_at).toBeNull();
    });

    it('preserves timestamp precision', () => {
      const canonical = createPendingMembership({
        invited_at: new Date('2024-06-15T14:30:00.000Z'),
        expires_at: new Date('2024-06-22T14:30:00.000Z'),
      });
      const v3Wire = createV3WireOrganizationMembership(canonical);
      const parsed = v3MembershipSchema.parse(v3Wire);

      expect(parsed.invited_at!.getTime()).toBe(
        canonical.invited_at!.getTime()
      );
      expect(parsed.expires_at!.getTime()).toBe(
        canonical.expires_at!.getTime()
      );
    });
  });
});

// -----------------------------------------------------------------------------
// V2 Default Values
// -----------------------------------------------------------------------------

describe('V2 Organization Membership Default Values', () => {
  it('applies default for role when missing', () => {
    const wire = createV2WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { role, ...wireWithoutRole } = wire;

    const parsed = v2MembershipSchema.parse(wireWithoutRole);

    expect(parsed.role).toBe('member');
  });

  it('applies default for status when missing', () => {
    const wire = createV2WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { status, ...wireWithoutStatus } = wire;

    const parsed = v2MembershipSchema.parse(wireWithoutStatus);

    expect(parsed.status).toBe('active');
  });

  it('applies default for expired when missing', () => {
    const wire = createV2WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { expired, ...wireWithoutExpired } = wire;

    const parsed = v2MembershipSchema.parse(wireWithoutExpired);

    expect(parsed.expired).toBe(false);
  });

  it('applies default for resend_count when missing', () => {
    const wire = createV2WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { resend_count, ...wireWithoutResendCount } = wire;

    const parsed = v2MembershipSchema.parse(wireWithoutResendCount);

    expect(parsed.resend_count).toBe(0);
  });

  it('applies null defaults for nullable fields', () => {
    const wire = createV2WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const {
      organization_id,
      email,
      invited_by,
      invited_at,
      expires_at,
      token,
      ...wireMinimal
    } = wire;

    const parsed = v2MembershipSchema.parse(wireMinimal);

    expect(parsed.organization_id).toBeNull();
    expect(parsed.email).toBeNull();
    expect(parsed.invited_by).toBeNull();
    expect(parsed.invited_at).toBeNull();
    expect(parsed.expires_at).toBeNull();
    expect(parsed.token).toBeNull();
  });
});

// -----------------------------------------------------------------------------
// V2 Transform Behavior
// -----------------------------------------------------------------------------

describe('V2 Organization Membership Transform Behavior', () => {
  describe('boolean transforms', () => {
    // V2 only accepts string-encoded booleans
    it.each([
      ['true', true],
      ['false', false],
      ['1', true],
      ['0', false],
    ])('transforms %p to %p for expired', (input, expected) => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).expired = input;

      const parsed = v2MembershipSchema.parse(wire);

      expect(parsed.expired).toBe(expected);
    });
  });

  describe('number transforms', () => {
    // V2 only accepts string-encoded numbers
    it.each([
      ['0', 0],
      ['1', 1],
      ['5', 5],
    ])('transforms %p to %p for resend_count', (input, expected) => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).resend_count = input;

      const parsed = v2MembershipSchema.parse(wire);

      expect(parsed.resend_count).toBe(expected);
    });
  });

  describe('date transforms', () => {
    it('transforms ISO string to Date for invited_at', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      const isoDate = '2024-06-15T10:00:00.000Z';
      (wire as Record<string, unknown>).invited_at = isoDate;

      const parsed = v2MembershipSchema.parse(wire);

      expect(parsed.invited_at).toBeInstanceOf(Date);
      expect(parsed.invited_at!.toISOString()).toBe(isoDate);
    });

    it('handles null invited_at', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).invited_at = null;

      const parsed = v2MembershipSchema.parse(wire);

      expect(parsed.invited_at).toBeNull();
    });
  });
});

// -----------------------------------------------------------------------------
// Comparison Helper Tests
// -----------------------------------------------------------------------------

describe('Comparison Helpers', () => {
  it('compareCanonicalOrganizationMembership detects no differences for identical memberships', () => {
    const a = createCanonicalOrganizationMembership();
    const b = createCanonicalOrganizationMembership();

    const result = compareCanonicalOrganizationMembership(a, b);
    expect(result.equal).toBe(true);
    expect(result.differences).toHaveLength(0);
  });

  it('compareCanonicalOrganizationMembership detects field differences', () => {
    const a = createCanonicalOrganizationMembership({ status: 'active' });
    const b = createCanonicalOrganizationMembership({ status: 'pending' });

    const result = compareCanonicalOrganizationMembership(a, b);
    expect(result.equal).toBe(false);
    expect(result.differences).toContain('status: "active" !== "pending"');
  });

  it('compareCanonicalOrganizationMembership handles Date comparison', () => {
    const a = createPendingMembership({
      invited_at: new Date('2024-01-15T10:00:00.000Z'),
    });
    const b = createPendingMembership({
      invited_at: new Date('2024-01-16T10:00:00.000Z'),
    });

    const result = compareCanonicalOrganizationMembership(a, b);
    expect(result.equal).toBe(false);
    expect(result.differences.some((d) => d.includes('invited_at'))).toBe(true);
  });

  it('compareCanonicalOrganizationMembership handles null vs Date', () => {
    const a = createCanonicalOrganizationMembership({ invited_at: null });
    const b = createPendingMembership();

    const result = compareCanonicalOrganizationMembership(a, b);
    expect(result.equal).toBe(false);
    expect(result.differences.some((d) => d.includes('invited_at'))).toBe(true);
  });
});
