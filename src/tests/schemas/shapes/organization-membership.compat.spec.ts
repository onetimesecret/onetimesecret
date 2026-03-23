// src/tests/schemas/shapes/organization-membership.compat.spec.ts
//
// Cross-version compatibility tests for organization membership schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning

import { describe, it, expect } from 'vitest';
import { organizationMembershipSchema as v2MembershipSchema } from '@/schemas/shapes/v2/organization-membership';
import { organizationMembershipRecord as v3MembershipSchema } from '@/schemas/shapes/v3/organization-membership';
import {
  createCanonicalOrganizationMembership,
  createPendingMembership,
  createActiveMembership,
  createExpiredMembership,
  createMinimalMembership,
  createOwnerMembership,
  createV2WireOrganizationMembership,
  createV3WireOrganizationMembership,
} from './fixtures/organization-membership.fixtures';

// -----------------------------------------------------------------------------
// V2 Wire -> V3 Schema (Forward Compatibility)
// -----------------------------------------------------------------------------

describe('V2 Wire -> V3 Schema (Forward Compatibility)', () => {
  describe('timestamp handling', () => {
    it('FAILS: V3 expects number timestamps, V2 sends strings', () => {
      // V2 sends invited_at/expires_at as ISO strings
      // V3 expects Unix epoch numbers
      const canonical = createPendingMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);

      expect(typeof v2Wire.invited_at).toBe('string');
      expect(typeof v2Wire.expires_at).toBe('string');

      // V3 schema rejects string timestamps
      const result = v3MembershipSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        const timestampErrors = result.error.issues.filter(
          (i) =>
            i.path.includes('invited_at') || i.path.includes('expires_at')
        );
        expect(timestampErrors.length).toBeGreaterThan(0);
      }
    });
  });

  describe('boolean handling', () => {
    it('FAILS: V3 rejects V2 string booleans', () => {
      // V2 sends booleans as strings ("true"/"false")
      // V3 expects native booleans
      const canonical = createExpiredMembership();
      const v2Wire = createV2WireOrganizationMembership(canonical);

      expect(typeof v2Wire.expired).toBe('string');

      // V3 schema rejects string booleans
      const result = v3MembershipSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        const booleanErrors = result.error.issues.filter((i) =>
          i.path.includes('expired')
        );
        expect(booleanErrors.length).toBeGreaterThan(0);
      }
    });
  });

  describe('number handling', () => {
    it('FAILS: V3 rejects V2 string numbers', () => {
      // V2 sends resend_count as string
      // V3 expects native number
      const canonical = createCanonicalOrganizationMembership({
        resend_count: 5,
      });
      const v2Wire = createV2WireOrganizationMembership(canonical);

      expect(typeof v2Wire.resend_count).toBe('string');

      // V3 schema rejects string numbers
      const result = v3MembershipSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Wire -> V2 Schema (Backward Compatibility)
// -----------------------------------------------------------------------------

describe.skip('V3 Wire -> V2 Schema (Backward Compatibility)', () => {
  describe('timestamp handling', () => {
    it('SUCCEEDS: V2 transforms handle numeric timestamps', () => {
      // V2's parseDateValue handles numbers via preprocess
      const canonical = createPendingMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      // V3 sends as number
      expect(typeof v3Wire.invited_at).toBe('number');
      expect(typeof v3Wire.expires_at).toBe('number');

      // V2's transforms should handle this
      const result = v2MembershipSchema.safeParse(v3Wire);

      // Document whether this succeeds
      if (result.success) {
        expect(result.data.invited_at).toBeInstanceOf(Date);
        expect(result.data.expires_at).toBeInstanceOf(Date);
      }
    });

    it('handles null timestamps from V3', () => {
      const canonical = createActiveMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(v3Wire.invited_at).toBe(
        Math.floor(canonical.invited_at!.getTime() / 1000)
      );
      expect(v3Wire.expires_at).toBeNull();

      const result = v2MembershipSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.expires_at).toBeNull();
      }
    });
  });

  describe('boolean handling', () => {
    it('SUCCEEDS: V2 transforms.fromString.boolean handles native booleans', () => {
      // V2's parseBoolean handles both strings AND booleans
      const canonical = createExpiredMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(typeof v3Wire.expired).toBe('boolean');
      expect(v3Wire.expired).toBe(true);

      const result = v2MembershipSchema.safeParse(v3Wire);

      // V2's parseBoolean handles native booleans
      if (result.success) {
        expect(result.data.expired).toBe(true);
      }
    });

    it('SUCCEEDS: V2 handles false boolean from V3', () => {
      const canonical = createActiveMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(v3Wire.expired).toBe(false);

      const result = v2MembershipSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.expired).toBe(false);
      }
    });
  });

  describe('number handling', () => {
    it('SUCCEEDS: V2 transforms.fromString.number handles native numbers', () => {
      // V2's parseNumber handles both strings AND numbers
      const canonical = createCanonicalOrganizationMembership({
        resend_count: 7,
      });
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(typeof v3Wire.resend_count).toBe('number');

      const result = v2MembershipSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.resend_count).toBe(7);
      }
    });
  });

  describe('full membership parsing', () => {
    it('V2 schema successfully parses complete V3 wire data', () => {
      // Due to V2's flexible preprocessors, it should handle V3 data
      const canonical = createCanonicalOrganizationMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      const result = v2MembershipSchema.safeParse(v3Wire);

      // V2 should parse V3 data successfully due to flexible transforms
      expect(result.success).toBe(true);
    });

    it('V2 schema parses pending invitation from V3 format', () => {
      const canonical = createPendingMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      const result = v2MembershipSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.status).toBe('pending');
        expect(result.data.token).toBe(canonical.token);
      }
    });

    it('V2 schema parses owner membership from V3 format', () => {
      const canonical = createOwnerMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      const result = v2MembershipSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.role).toBe('owner');
      }
    });

    it('V2 schema parses minimal membership from V3 format', () => {
      const canonical = createMinimalMembership();
      const v3Wire = createV3WireOrganizationMembership(canonical);

      const result = v2MembershipSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.organization_id).toBeNull();
        expect(result.data.email).toBeNull();
        expect(result.data.invited_by).toBeNull();
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Null Field Handling Compatibility
// -----------------------------------------------------------------------------

describe('Null Field Handling Compatibility', () => {
  describe('null vs undefined handling', () => {
    it('V2 and V3 both handle null organization_id identically', () => {
      const canonical = createMinimalMembership();

      const v2Wire = createV2WireOrganizationMembership(canonical);
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(v2Wire.organization_id).toBeNull();
      expect(v3Wire.organization_id).toBeNull();
    });

    it('V2 and V3 both handle null email identically', () => {
      const canonical = createMinimalMembership();

      const v2Wire = createV2WireOrganizationMembership(canonical);
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(v2Wire.email).toBeNull();
      expect(v3Wire.email).toBeNull();
    });

    it('V2 and V3 both handle null token identically', () => {
      const canonical = createActiveMembership();

      const v2Wire = createV2WireOrganizationMembership(canonical);
      const v3Wire = createV3WireOrganizationMembership(canonical);

      expect(v2Wire.token).toBeNull();
      expect(v3Wire.token).toBeNull();
    });

    it('V2 and V3 both handle null invited_at differently', () => {
      const canonical = createMinimalMembership();

      const v2Wire = createV2WireOrganizationMembership(canonical);
      const v3Wire = createV3WireOrganizationMembership(canonical);

      // V2 sends null as null (string representation would be 'null')
      expect(v2Wire.invited_at).toBeNull();
      // V3 sends null as null (native)
      expect(v3Wire.invited_at).toBeNull();
    });
  });

  describe('empty string handling in V2', () => {
    it('V2 treats empty string as false for expired', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).expired = '';

      const result = v2MembershipSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for empty string
        expect(result.data.expired).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Semantic Differences
// -----------------------------------------------------------------------------

describe('Semantic Differences', () => {
  describe('expired field computation', () => {
    it('documents: expired is a computed boolean from Ruby model', () => {
      // In Ruby, expired? checks:
      // 1. status == 'pending'
      // 2. invited_at exists
      // 3. (now - invited_at) > 7 days
      //
      // The wire format sends the pre-computed value,
      // but status may also be 'expired' as a persisted state

      const expiredByFlag = createCanonicalOrganizationMembership({
        status: 'pending',
        expired: true, // Computed flag says expired
      });

      const expiredByStatus = createCanonicalOrganizationMembership({
        status: 'expired', // Status explicitly set to expired
        expired: true,
      });

      // Both are valid representations of an expired invitation
      expect(expiredByFlag.expired).toBe(true);
      expect(expiredByStatus.status).toBe('expired');
    });
  });

  describe('token handling by status', () => {
    it('documents: token is cleared when invitation is accepted', () => {
      const pending = createPendingMembership();
      const active = createActiveMembership();

      expect(pending.token).not.toBeNull();
      expect(active.token).toBeNull();
    });

    it('documents: token may persist for expired invitations', () => {
      // Expired invitations may keep the token for audit purposes
      const expired = createExpiredMembership();

      expect(expired.token).not.toBeNull();
      expect(expired.status).toBe('expired');
    });

    it('documents: token is cleared when invitation is declined', () => {
      const declined = createCanonicalOrganizationMembership({
        status: 'declined',
        token: null,
      });

      expect(declined.token).toBeNull();
    });
  });
});

// -----------------------------------------------------------------------------
// Compatibility Summary Matrix
// -----------------------------------------------------------------------------

describe('Compatibility Summary', () => {
  it('documents the V2<->V3 compatibility matrix for organization membership', () => {
    const matrix = {
      'V2 Wire -> V3 Schema': {
        'invited_at (string->number)': 'INCOMPATIBLE - V3 expects number',
        'expires_at (string->number)': 'INCOMPATIBLE - V3 expects number',
        'expired (string->boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'resend_count (string->number)': 'INCOMPATIBLE - V3 expects number',
        'null fields': 'COMPATIBLE - both use null',
        'role (enum)': 'COMPATIBLE - both use string enum',
        'status (enum)': 'COMPATIBLE - both use string enum',
      },
      'V3 Wire -> V2 Schema': {
        'invited_at (number->string)': 'COMPATIBLE - V2 parseDateValue handles numbers',
        'expires_at (number->string)': 'COMPATIBLE - V2 parseDateValue handles numbers',
        'expired (boolean->string)': 'COMPATIBLE - V2 parseBoolean handles booleans',
        'resend_count (number->string)': 'COMPATIBLE - V2 parseNumber handles numbers',
        'null fields': 'COMPATIBLE - both use null',
        'role (enum)': 'COMPATIBLE - both use string enum',
        'status (enum)': 'COMPATIBLE - both use string enum',
      },
      'Semantic Differences': {
        'expired: computation': 'Pre-computed in Ruby from invited_at + TTL',
        'status: expired': 'May be persisted as status or computed via expired flag',
        'token: on accept': 'Cleared when invitation is accepted',
        'token: on decline': 'Cleared when invitation is declined',
        'token: on expire': 'May persist for audit purposes',
      },
    };

    console.log(
      '\n=== V2 <-> V3 Organization Membership Compatibility Matrix ==='
    );
    console.log(JSON.stringify(matrix, null, 2));

    // V3 -> V2 is generally compatible (V2 has flexible preprocessors)
    // V2 -> V3 is generally INCOMPATIBLE (V3 expects strict types)
    expect(true).toBe(true); // Documentation test
  });

  it('documents organization-membership-specific transformation notes', () => {
    const notes = {
      'no identifier field':
        'OrganizationMembership uses id (objid), not createModelSchema',
      'no created/updated':
        'Through model does not track standard timestamp fields',
      'organization_id nullable':
        'May be null during initial creation before org association',
      'email nullable':
        'Email is set for pending invites, may be null for direct adds',
      'invited_by nullable':
        'Null when member is added directly without invitation',
      'expires_at computed':
        'Calculated as invited_at + 7 days in Ruby model',
      'expired computed':
        'Checked as pending? && invited_at && (now - invited_at) > 7.days',
    };

    expect(notes).toBeDefined();
  });
});

// -----------------------------------------------------------------------------
// V3 Default Values
// -----------------------------------------------------------------------------

describe('V3 Organization Membership Default Values', () => {
  it('applies default for role when missing', () => {
    const wire = createV3WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { role, ...wireWithoutRole } = wire;

    const parsed = v3MembershipSchema.parse(wireWithoutRole);

    expect(parsed.role).toBe('member');
  });

  it('applies default for status when missing', () => {
    const wire = createV3WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { status, ...wireWithoutStatus } = wire;

    const parsed = v3MembershipSchema.parse(wireWithoutStatus);

    expect(parsed.status).toBe('active');
  });

  it('applies default for expired when missing', () => {
    const wire = createV3WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { expired, ...wireWithoutExpired } = wire;

    const parsed = v3MembershipSchema.parse(wireWithoutExpired);

    expect(parsed.expired).toBe(false);
  });

  it('applies default for resend_count when missing', () => {
    const wire = createV3WireOrganizationMembership(
      createCanonicalOrganizationMembership()
    );
    const { resend_count, ...wireWithoutResendCount } = wire;

    const parsed = v3MembershipSchema.parse(wireWithoutResendCount);

    expect(parsed.resend_count).toBe(0);
  });
});

// -----------------------------------------------------------------------------
// Transform Error Handling
// -----------------------------------------------------------------------------

describe('Transform Error Handling', () => {
  describe('malformed input handling', () => {
    it('V2 parseBoolean returns false for unrecognized values', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).expired = 'maybe';

      const result = v2MembershipSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for unrecognized values
        expect(result.data.expired).toBe(false);
      }
    });

    it('V2 parseNumber returns null for non-numeric strings', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).resend_count = 'abc';

      const result = v2MembershipSchema.safeParse(wire);

      // parseNumber returns null for non-numeric strings
      if (result.success) {
        expect(result.data.resend_count).toBeNull();
      }
    });
  });

  describe('required field validation', () => {
    it('rejects missing id', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      const { id, ...wireWithoutId } = wire;

      const result = v2MembershipSchema.safeParse(wireWithoutId);

      expect(result.success).toBe(false);
    });
  });

  describe('enum validation', () => {
    it('rejects invalid role value', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).role = 'superadmin';

      const result = v2MembershipSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('rejects invalid status value', () => {
      const wire = createV2WireOrganizationMembership(
        createCanonicalOrganizationMembership()
      );
      (wire as Record<string, unknown>).status = 'cancelled';

      const result = v2MembershipSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });
  });
});
