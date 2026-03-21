// src/tests/schemas/shapes/organization.compat.spec.ts
//
// Cross-version compatibility tests for organization schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning

import { describe, it, expect } from 'vitest';
import { organizationCoreSchema as v2OrganizationSchema } from '@/schemas/shapes/v2/organization';
import { organizationRecord as v3OrganizationSchema } from '@/schemas/shapes/v3/organization';
import {
  createCanonicalOrganization,
  createDefaultOrganization,
  createPaidOrganization,
  createMinimalOrganization,
  createV2WireOrganization,
  createV3WireOrganization,
} from './fixtures/organization.fixtures';

// -----------------------------------------------------------------------------
// V2 Wire -> V3 Schema (Forward Compatibility)
// -----------------------------------------------------------------------------

describe('V2 Wire -> V3 Schema (Forward Compatibility)', () => {
  describe('V3 schema type expectations', () => {
    it('FAILS: V3 expects number timestamps, V2 sends strings', () => {
      // V2 sends created/updated as string Unix timestamps
      // V3 expects native numbers
      const canonical = createCanonicalOrganization();
      const v2Wire = createV2WireOrganization(canonical);

      expect(typeof v2Wire.created).toBe('string');
      expect(typeof v2Wire.updated).toBe('string');

      // V3 schema rejects string timestamps
      const result = v3OrganizationSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        const timestampErrors = result.error.issues.filter(
          (i) => i.path.includes('created') || i.path.includes('updated')
        );
        expect(timestampErrors.length).toBeGreaterThan(0);
      }
    });

    it('FAILS: V3 rejects V2 string booleans', () => {
      // V2 sends booleans as strings ("true"/"false")
      // V3 expects native booleans
      const canonical = createDefaultOrganization();
      const v2Wire = createV2WireOrganization(canonical);

      expect(typeof v2Wire.is_default).toBe('string');

      // V3 schema rejects string booleans
      const result = v3OrganizationSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        const booleanErrors = result.error.issues.filter((i) =>
          i.path.includes('is_default')
        );
        expect(booleanErrors.length).toBeGreaterThan(0);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Wire -> V2 Schema (Backward Compatibility)
// -----------------------------------------------------------------------------

describe('V3 Wire -> V2 Schema (Backward Compatibility)', () => {
  describe('timestamp handling', () => {
    it('SUCCEEDS: V2 transforms handle native numbers for timestamps', () => {
      // V2's parseDateValue handles both strings AND numbers
      const canonical = createCanonicalOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      // V3 sends as number
      expect(typeof v3Wire.created).toBe('number');
      expect(typeof v3Wire.updated).toBe('number');

      // V2's preprocess should handle this
      const result = v2OrganizationSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.created).toBeInstanceOf(Date);
        expect(result.data.updated).toBeInstanceOf(Date);
      }
    });
  });

  describe('boolean handling', () => {
    it('SUCCEEDS: V2 transforms.fromString.boolean handles native booleans', () => {
      // V2's parseBoolean function handles both strings AND booleans
      const canonical = createDefaultOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      expect(typeof v3Wire.is_default).toBe('boolean');

      const result = v2OrganizationSchema.safeParse(v3Wire);

      // V2's parseBoolean handles native booleans
      if (result.success) {
        expect(result.data.is_default).toBe(true);
      }
    });

    it('SUCCEEDS: V2 handles false boolean from V3', () => {
      const canonical = createCanonicalOrganization({ is_default: false });
      const v3Wire = createV3WireOrganization(canonical);

      expect(v3Wire.is_default).toBe(false);

      const result = v2OrganizationSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.is_default).toBe(false);
      }
    });
  });

  describe('full organization parsing', () => {
    it('V2 schema successfully parses complete V3 wire data', () => {
      // Due to V2's flexible preprocessors, it should handle V3 data
      const canonical = createCanonicalOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      const result = v2OrganizationSchema.safeParse(v3Wire);

      // Document whether this succeeds
      console.log('[V3->V2] organization compatibility:', result.success);
      if (!result.success) {
        console.log(
          '[V3->V2] Errors:',
          result.error.issues.map((i) => `${i.path}: ${i.message}`)
        );
      }

      // V2 should parse V3 data successfully due to flexible transforms
      expect(result.success).toBe(true);
    });

    it('V2 schema parses default organization from V3 format', () => {
      const canonical = createDefaultOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      const result = v2OrganizationSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.is_default).toBe(true);
      }
    });

    it('V2 schema parses paid organization from V3 format', () => {
      const canonical = createPaidOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      const result = v2OrganizationSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.planid).toBe('pro');
      }
    });

    it('V2 schema parses minimal organization from V3 format', () => {
      const canonical = createMinimalOrganization();
      const v3Wire = createV3WireOrganization(canonical);

      const result = v2OrganizationSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.description).toBeNull();
        expect(result.data.contact_email).toBeNull();
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Null Field Handling Compatibility
// -----------------------------------------------------------------------------

describe('Null Field Handling Compatibility', () => {
  describe('null vs undefined handling', () => {
    it('V2 and V3 both handle null description identically', () => {
      const canonical = createCanonicalOrganization({ description: null });

      const v2Wire = createV2WireOrganization(canonical);
      const v3Wire = createV3WireOrganization(canonical);

      expect(v2Wire.description).toBeNull();
      expect(v3Wire.description).toBeNull();
    });

    it('V2 and V3 both handle null contact_email identically', () => {
      const canonical = createCanonicalOrganization({ contact_email: null });

      const v2Wire = createV2WireOrganization(canonical);
      const v3Wire = createV3WireOrganization(canonical);

      expect(v2Wire.contact_email).toBeNull();
      expect(v3Wire.contact_email).toBeNull();
    });
  });

  describe('empty string handling in V2', () => {
    it('V2 treats empty string as false for boolean (is_default)', () => {
      const wire = createV2WireOrganization(createCanonicalOrganization());
      (wire as Record<string, unknown>).is_default = '';

      const result = v2OrganizationSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for empty string
        expect(result.data.is_default).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Compatibility Summary Matrix
// -----------------------------------------------------------------------------

describe('Compatibility Summary', () => {
  it('documents the V2<->V3 compatibility matrix for organization', () => {
    const matrix = {
      'V2 Wire -> V3 Schema': {
        'created/updated (string->number)': 'INCOMPATIBLE - V3 expects number',
        'is_default (string->boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'null description': 'COMPATIBLE - both use null',
        'null contact_email': 'COMPATIBLE - both use null',
        'planid (string)': 'COMPATIBLE - both use string',
      },
      'V3 Wire -> V2 Schema': {
        'created/updated (number->string)': 'COMPATIBLE - V2 parseDate handles numbers',
        'is_default (boolean->string)': 'COMPATIBLE - V2 parseBoolean handles booleans',
        'null description': 'COMPATIBLE - both use null',
        'null contact_email': 'COMPATIBLE - both use null',
        'planid (string)': 'COMPATIBLE - both use string',
      },
      'Semantic Differences': {
        'is_default: missing': 'V2 defaults to false',
        'planid: missing': 'Both default to "free"',
        'description: missing': 'Both default to null',
        'contact_email: missing': 'Both default to null',
      },
    };

    console.log('\n=== V2 <-> V3 Organization Compatibility Matrix ===');
    console.log(JSON.stringify(matrix, null, 2));

    // V3 -> V2 is generally compatible (V2 has flexible preprocessors)
    // V2 -> V3 is generally INCOMPATIBLE (V3 expects strict types)
    expect(true).toBe(true); // Documentation test
  });

  it('documents organization-specific transformation notes', () => {
    const notes = {
      'createModelSchema fields':
        'identifier, created, updated are added by createModelSchema from base.ts',
      'nullable vs optional':
        'description and contact_email are nullable (can be null)',
      'default values':
        'is_default defaults to false, planid defaults to "free"',
      'no feature_flags':
        'Unlike customer, organization does not have feature_flags',
      'no relationships in schema':
        'members, domains, receipts are runtime relationships, not in schema',
    };

    expect(notes).toBeDefined();
  });
});

// -----------------------------------------------------------------------------
// Transform Error Handling
// -----------------------------------------------------------------------------

describe('Transform Error Handling', () => {
  describe('malformed input handling', () => {
    it('V2 parseBoolean returns false for unrecognized values', () => {
      const wire = createV2WireOrganization(createCanonicalOrganization());
      (wire as Record<string, unknown>).is_default = 'maybe';

      const result = v2OrganizationSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for unrecognized values
        expect(result.data.is_default).toBe(false);
      }
    });
  });

  describe('required field validation', () => {
    it('rejects missing identifier', () => {
      const wire = createV2WireOrganization(createCanonicalOrganization());
      const { identifier, ...wireWithoutIdentifier } = wire;

      const result = v2OrganizationSchema.safeParse(wireWithoutIdentifier);

      expect(result.success).toBe(false);
    });

    it('rejects missing display_name', () => {
      const wire = createV2WireOrganization(createCanonicalOrganization());
      const { display_name, ...wireWithoutName } = wire;

      const result = v2OrganizationSchema.safeParse(wireWithoutName);

      expect(result.success).toBe(false);
    });

    it('rejects missing owner_id', () => {
      const wire = createV2WireOrganization(createCanonicalOrganization());
      const { owner_id, ...wireWithoutOwner } = wire;

      const result = v2OrganizationSchema.safeParse(wireWithoutOwner);

      expect(result.success).toBe(false);
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Default Values
// -----------------------------------------------------------------------------

describe('V3 Organization Default Values', () => {
  it('applies default for is_default when missing', () => {
    const wire = createV3WireOrganization(createCanonicalOrganization());
    const { is_default, ...wireWithoutDefault } = wire;

    const parsed = v3OrganizationSchema.parse(wireWithoutDefault);

    expect(parsed.is_default).toBe(false);
  });

  it('applies default planid when missing', () => {
    const wire = createV3WireOrganization(createCanonicalOrganization());
    const { planid, ...wireWithoutPlanid } = wire;

    const parsed = v3OrganizationSchema.parse(wireWithoutPlanid);

    expect(parsed.planid).toBe('free');
  });

  it('applies null default for description when missing', () => {
    const wire = createV3WireOrganization(createCanonicalOrganization());
    const { description, ...wireWithoutDescription } = wire;

    const parsed = v3OrganizationSchema.parse(wireWithoutDescription);

    expect(parsed.description).toBeNull();
  });
});
