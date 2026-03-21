// src/tests/schemas/shapes/organization.roundtrip.spec.ts
//
// Round-trip tests for organization schemas (V2 and V3).
// Verifies: canonical -> wire -> parse -> canonical preserves data.
//
// Purpose:
//   - Verify serializer functions match schema expectations
//   - Catch type mismatches between canonical and wire formats
//   - Document expected transform behavior
//
// Pattern:
//   1. Create canonical organization
//   2. Convert to wire format (V2 or V3)
//   3. Parse wire format with schema
//   4. Compare parsed result to original canonical

import { describe, it, expect } from 'vitest';
import { organizationCoreSchema as v2OrganizationSchema } from '@/schemas/shapes/v2/organization';
import { organizationRecord as v3OrganizationSchema } from '@/schemas/shapes/v3/organization';
import {
  createCanonicalOrganization,
  createDefaultOrganization,
  createPaidOrganization,
  createMinimalOrganization,
  createVerboseOrganization,
  createOldOrganization,
  createV2WireOrganization,
  createV3WireOrganization,
  compareCanonicalOrganization,
  type OrganizationCanonical,
} from './fixtures/organization.fixtures';

// -----------------------------------------------------------------------------
// V2 Organization Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V2 Organization Round-Trip', () => {
  describe('organizationCoreSchema', () => {
    it('round-trips a standard organization', () => {
      const canonical = createCanonicalOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      // Verify all fields match
      expect(parsed.identifier).toBe(canonical.identifier);
      expect(parsed.objid).toBe(canonical.objid);
      expect(parsed.extid).toBe(canonical.extid);
      expect(parsed.display_name).toBe(canonical.display_name);
      expect(parsed.description).toBe(canonical.description);
      expect(parsed.owner_id).toBe(canonical.owner_id);
      expect(parsed.contact_email).toBe(canonical.contact_email);
      expect(parsed.is_default).toBe(canonical.is_default);
      expect(parsed.planid).toBe(canonical.planid);

      // Timestamps (compare as milliseconds)
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });

    it('round-trips a default organization (is_default=true)', () => {
      const canonical = createDefaultOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.is_default).toBe(true);
      expect(parsed.display_name).toBe(canonical.display_name);
    });

    it('round-trips a paid organization (planid=pro)', () => {
      const canonical = createPaidOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.planid).toBe('pro');
      expect(parsed.contact_email).toBe(canonical.contact_email);
    });

    it('round-trips a minimal organization (null fields)', () => {
      const canonical = createMinimalOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.description).toBeNull();
      expect(parsed.contact_email).toBeNull();
    });

    it('preserves long display names and descriptions', () => {
      const canonical = createVerboseOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.display_name).toBe(canonical.display_name);
      expect(parsed.description).toBe(canonical.description);
    });

    it('handles different created/updated timestamps', () => {
      const canonical = createOldOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      // created should be earlier than updated
      expect(parsed.created.getTime()).toBeLessThan(parsed.updated.getTime());
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });

    it('uses compareCanonicalOrganization for full equality check', () => {
      const canonical = createCanonicalOrganization();
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      const comparison = compareCanonicalOrganization(
        canonical,
        parsed as OrganizationCanonical
      );

      expect(comparison.equal).toBe(true);
      expect(comparison.differences).toEqual([]);
    });
  });

  describe('edge cases', () => {
    it('handles empty description (null)', () => {
      const canonical = createCanonicalOrganization({ description: null });
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.description).toBeNull();
    });

    it('handles empty contact_email (null)', () => {
      const canonical = createCanonicalOrganization({ contact_email: null });
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.contact_email).toBeNull();
    });

    it('handles special characters in display_name', () => {
      const canonical = createCanonicalOrganization({
        display_name: 'Acme & Co. (International)',
      });
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.display_name).toBe('Acme & Co. (International)');
    });

    it('handles email with plus addressing', () => {
      const canonical = createCanonicalOrganization({
        contact_email: 'billing+test@example.com',
      });
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.contact_email).toBe('billing+test@example.com');
    });

    it('handles unicode in description', () => {
      const canonical = createCanonicalOrganization({
        description: 'International: 日本語, Deutsch, Francais',
      });
      const v2Wire = createV2WireOrganization(canonical);
      const parsed = v2OrganizationSchema.parse(v2Wire);

      expect(parsed.description).toBe(
        'International: 日本語, Deutsch, Francais'
      );
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Organization Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V3 Organization Round-Trip', () => {
  describe('organizationRecord', () => {
    it('round-trips a standard organization', () => {
      const canonical = createCanonicalOrganization();
      const v3Wire = createV3WireOrganization(canonical);
      const parsed = v3OrganizationSchema.parse(v3Wire);

      // Verify all fields match
      expect(parsed.identifier).toBe(canonical.identifier);
      expect(parsed.objid).toBe(canonical.objid);
      expect(parsed.extid).toBe(canonical.extid);
      expect(parsed.display_name).toBe(canonical.display_name);
      expect(parsed.description).toBe(canonical.description);
      expect(parsed.owner_id).toBe(canonical.owner_id);
      expect(parsed.contact_email).toBe(canonical.contact_email);
      expect(parsed.is_default).toBe(canonical.is_default);
      expect(parsed.planid).toBe(canonical.planid);

      // Timestamps (compare as milliseconds)
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });

    it('round-trips a default organization (is_default=true)', () => {
      const canonical = createDefaultOrganization();
      const v3Wire = createV3WireOrganization(canonical);
      const parsed = v3OrganizationSchema.parse(v3Wire);

      expect(parsed.is_default).toBe(true);
      expect(parsed.display_name).toBe(canonical.display_name);
    });

    it('round-trips a paid organization (planid=pro)', () => {
      const canonical = createPaidOrganization();
      const v3Wire = createV3WireOrganization(canonical);
      const parsed = v3OrganizationSchema.parse(v3Wire);

      expect(parsed.planid).toBe('pro');
      expect(parsed.contact_email).toBe(canonical.contact_email);
    });

    it('round-trips a minimal organization (null fields)', () => {
      const canonical = createMinimalOrganization();
      const v3Wire = createV3WireOrganization(canonical);
      const parsed = v3OrganizationSchema.parse(v3Wire);

      expect(parsed.description).toBeNull();
      expect(parsed.contact_email).toBeNull();
    });

    it('handles different created/updated timestamps', () => {
      const canonical = createOldOrganization();
      const v3Wire = createV3WireOrganization(canonical);
      const parsed = v3OrganizationSchema.parse(v3Wire);

      // created should be earlier than updated
      expect(parsed.created.getTime()).toBeLessThan(parsed.updated.getTime());
      expect(parsed.created.getTime()).toBe(canonical.created.getTime());
      expect(parsed.updated.getTime()).toBe(canonical.updated.getTime());
    });

    it('uses compareCanonicalOrganization for full equality check', () => {
      const canonical = createCanonicalOrganization();
      const v3Wire = createV3WireOrganization(canonical);
      const parsed = v3OrganizationSchema.parse(v3Wire);

      const comparison = compareCanonicalOrganization(
        canonical,
        parsed as OrganizationCanonical
      );

      expect(comparison.equal).toBe(true);
      expect(comparison.differences).toEqual([]);
    });
  });

  describe('V3 wire format types', () => {
    it('sends timestamps as numbers', () => {
      const canonical = createCanonicalOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      expect(typeof v3Wire.created).toBe('number');
      expect(typeof v3Wire.updated).toBe('number');
    });

    it('sends booleans as native booleans', () => {
      const canonical = createDefaultOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      expect(typeof v3Wire.is_default).toBe('boolean');
      expect(v3Wire.is_default).toBe(true);
    });
  });
});

// -----------------------------------------------------------------------------
// V2 Default Values
// -----------------------------------------------------------------------------

describe('V2 Organization Default Values', () => {
  it('applies default for is_default when missing', () => {
    const wire = createV2WireOrganization(createCanonicalOrganization());
    // Remove is_default to test default
    const { is_default, ...wireWithoutDefault } = wire;

    const parsed = v2OrganizationSchema.parse(wireWithoutDefault);

    expect(parsed.is_default).toBe(false);
  });

  it('applies default planid when missing', () => {
    const wire = createV2WireOrganization(createCanonicalOrganization());
    const { planid, ...wireWithoutPlanid } = wire;

    const parsed = v2OrganizationSchema.parse(wireWithoutPlanid);

    expect(parsed.planid).toBe('free');
  });

  it('applies null default for description when missing', () => {
    const wire = createV2WireOrganization(createCanonicalOrganization());
    const { description, ...wireWithoutDescription } = wire;

    const parsed = v2OrganizationSchema.parse(wireWithoutDescription);

    expect(parsed.description).toBeNull();
  });

  it('applies null default for contact_email when missing', () => {
    const wire = createV2WireOrganization(createCanonicalOrganization());
    const { contact_email, ...wireWithoutEmail } = wire;

    const parsed = v2OrganizationSchema.parse(wireWithoutEmail);

    expect(parsed.contact_email).toBeNull();
  });
});

// -----------------------------------------------------------------------------
// V2 Transform Behavior
// -----------------------------------------------------------------------------

describe('V2 Organization Transform Behavior', () => {
  describe('boolean transforms', () => {
    it.each([
      ['true', true],
      ['false', false],
      ['1', true],
      ['0', false],
      [true, true],
      [false, false],
    ])('transforms %p to %p for is_default', (input, expected) => {
      const wire = createV2WireOrganization(createCanonicalOrganization());
      (wire as Record<string, unknown>).is_default = input;

      const parsed = v2OrganizationSchema.parse(wire);

      expect(parsed.is_default).toBe(expected);
    });
  });

  describe('date transforms', () => {
    it('transforms Unix timestamp string to Date for created', () => {
      const timestamp = Math.floor(Date.now() / 1000);
      const wire = createV2WireOrganization(createCanonicalOrganization());
      (wire as Record<string, unknown>).created = String(timestamp);

      const parsed = v2OrganizationSchema.parse(wire);

      expect(parsed.created).toBeInstanceOf(Date);
      expect(parsed.created.getTime()).toBe(timestamp * 1000);
    });

    it('handles numeric timestamps (V3 format in V2 parser)', () => {
      const timestamp = Math.floor(Date.now() / 1000);
      const wire = createV2WireOrganization(createCanonicalOrganization());
      (wire as Record<string, unknown>).created = timestamp;

      const parsed = v2OrganizationSchema.parse(wire);

      expect(parsed.created).toBeInstanceOf(Date);
    });
  });
});

// -----------------------------------------------------------------------------
// Plan Variations
// -----------------------------------------------------------------------------

describe('Organization Plan Variations', () => {
  const plans = ['free', 'pro', 'enterprise', 'custom'];

  it.each(plans)('round-trips organization with planid=%s', (planid) => {
    const canonical = createCanonicalOrganization({ planid });
    const v2Wire = createV2WireOrganization(canonical);
    const parsed = v2OrganizationSchema.parse(v2Wire);

    expect(parsed.planid).toBe(planid);
  });

  it.each(plans)('V3 round-trips organization with planid=%s', (planid) => {
    const canonical = createCanonicalOrganization({ planid });
    const v3Wire = createV3WireOrganization(canonical);
    const parsed = v3OrganizationSchema.parse(v3Wire);

    expect(parsed.planid).toBe(planid);
  });
});
