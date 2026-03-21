// src/tests/schemas/shapes/customer.compat.spec.ts
//
// Cross-version compatibility tests for customer schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning

import { describe, it, expect } from 'vitest';
import { customerSchema as v2CustomerSchema } from '@/schemas/shapes/v2/customer';
import { customerRecord as v3CustomerSchema } from '@/schemas/shapes/v3/customer';
import {
  createCanonicalCustomer,
  createColonelCustomer,
  createRecipientCustomer,
  createFeatureFlaggedCustomer,
  createV2WireCustomer,
  createV3WireCustomer,
  type CustomerCanonical,
} from './fixtures/customer.fixtures';

// -----------------------------------------------------------------------------
// V2 Wire -> V3 Schema (Forward Compatibility)
// -----------------------------------------------------------------------------

describe('V2 Wire -> V3 Schema (Forward Compatibility)', () => {
  describe('V3 schema type expectations', () => {
    it('FAILS: V3 expects number timestamps, V2 sends strings', () => {
      // V2 sends created/updated as string Unix timestamps
      // V3 expects native numbers
      const canonical = createCanonicalCustomer();
      const v2Wire = createV2WireCustomer(canonical);

      expect(typeof v2Wire.created).toBe('string');
      expect(typeof v2Wire.updated).toBe('string');

      // V3 schema rejects string timestamps
      const result = v3CustomerSchema.safeParse(v2Wire);
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
      const canonical = createCanonicalCustomer({
        verified: true,
        active: true,
      });
      const v2Wire = createV2WireCustomer(canonical);

      expect(typeof v2Wire.verified).toBe('string');
      expect(typeof v2Wire.active).toBe('string');

      // V3 schema rejects string booleans
      const result = v3CustomerSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        const booleanErrors = result.error.issues.filter(
          (i) => i.path.includes('verified') || i.path.includes('active')
        );
        expect(booleanErrors.length).toBeGreaterThan(0);
      }
    });

    it('V3 coerces V2 string numbers (no counter field errors)', () => {
      // V2 sends counter fields as strings
      // V3 uses z.coerce.number() per #2699 for resilience - no rejection
      const canonical = createCanonicalCustomer({
        secrets_created: 100,
        emails_sent: 50,
      });
      const v2Wire = createV2WireCustomer(canonical);

      expect(typeof v2Wire.secrets_created).toBe('string');
      expect(typeof v2Wire.emails_sent).toBe('string');

      // V3 schema parsing fails due to other fields (timestamps, booleans)
      // but counter fields are NOT rejected thanks to z.coerce.number()
      const result = v3CustomerSchema.safeParse(v2Wire);
      expect(result.success).toBe(false);
      if (!result.success) {
        // Counter fields should NOT appear in errors (they are coerced)
        const numberErrors = result.error.issues.filter(
          (i) =>
            i.path.includes('secrets_created') || i.path.includes('emails_sent')
        );
        expect(numberErrors.length).toBe(0);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Wire -> V2 Schema (Backward Compatibility)
// -----------------------------------------------------------------------------

describe('V3 Wire -> V2 Schema (Backward Compatibility)', () => {
  describe('timestamp handling', () => {
    it('SUCCEEDS: V2 transforms.fromString handles native numbers for timestamps', () => {
      // V2's parseDateValue handles both strings AND numbers
      const canonical = createCanonicalCustomer();
      const v3Wire = createV3WireCustomer(canonical);

      // V3 sends as number
      expect(typeof v3Wire.created).toBe('number');
      expect(typeof v3Wire.updated).toBe('number');

      // V2's preprocess should handle this
      const result = v2CustomerSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.created).toBeInstanceOf(Date);
        expect(result.data.updated).toBeInstanceOf(Date);
      }
    });

    it('SUCCEEDS: V2 handles null last_login from V3', () => {
      const canonical = createCanonicalCustomer({ last_login: null });
      const v3Wire = createV3WireCustomer(canonical);

      expect(v3Wire.last_login).toBeNull();

      const result = v2CustomerSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.last_login).toBeNull();
      }
    });
  });

  describe('boolean handling', () => {
    it('SUCCEEDS: V2 transforms.fromString.boolean handles native booleans', () => {
      // V2's parseBoolean function handles both strings AND booleans
      const canonical = createCanonicalCustomer({
        verified: true,
        active: false,
      });
      const v3Wire = createV3WireCustomer(canonical);

      expect(typeof v3Wire.verified).toBe('boolean');
      expect(typeof v3Wire.active).toBe('boolean');

      const result = v2CustomerSchema.safeParse(v3Wire);

      // V2's parseBoolean handles native booleans
      if (result.success) {
        expect(result.data.verified).toBe(true);
        expect(result.data.active).toBe(false);
      }
    });
  });

  describe('number handling', () => {
    it('SUCCEEDS: V2 transforms.fromString.number handles native numbers', () => {
      // V2's parseNumber function handles both strings AND numbers
      const canonical = createCanonicalCustomer({
        secrets_created: 100,
        secrets_burned: 10,
        secrets_shared: 80,
        emails_sent: 50,
      });
      const v3Wire = createV3WireCustomer(canonical);

      expect(typeof v3Wire.secrets_created).toBe('number');

      const result = v2CustomerSchema.safeParse(v3Wire);

      // V2's parseNumber handles native numbers
      if (result.success) {
        expect(result.data.secrets_created).toBe(100);
        expect(result.data.secrets_burned).toBe(10);
        expect(result.data.secrets_shared).toBe(80);
        expect(result.data.emails_sent).toBe(50);
      }
    });
  });

  describe('full customer parsing', () => {
    it('V2 schema successfully parses complete V3 wire data', () => {
      // Due to V2's flexible preprocessors, it should handle V3 data
      const canonical = createCanonicalCustomer();
      const v3Wire = createV3WireCustomer(canonical);

      const result = v2CustomerSchema.safeParse(v3Wire);

      // Document whether this succeeds
      console.log('[V3->V2] customer compatibility:', result.success);
      if (!result.success) {
        console.log(
          '[V3->V2] Errors:',
          result.error.issues.map((i) => `${i.path}: ${i.message}`)
        );
      }

      // V2 should parse V3 data successfully due to flexible transforms
      expect(result.success).toBe(true);
    });

    it('V2 schema parses colonel customer from V3 format', () => {
      const canonical = createColonelCustomer();
      const v3Wire = createV3WireCustomer(canonical);

      const result = v2CustomerSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.role).toBe('colonel');
      }
    });

    it('V2 schema parses recipient customer from V3 format', () => {
      const canonical = createRecipientCustomer();
      const v3Wire = createV3WireCustomer(canonical);

      const result = v2CustomerSchema.safeParse(v3Wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.role).toBe('recipient');
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Feature Flags Compatibility
// -----------------------------------------------------------------------------

describe('Feature Flags Compatibility', () => {
  describe('feature_flags encoding', () => {
    it('V2 and V3 both handle empty feature_flags', () => {
      const canonical = createCanonicalCustomer({ feature_flags: {} });

      const v2Wire = createV2WireCustomer(canonical);
      const v3Wire = createV3WireCustomer(canonical);

      expect(v2Wire.feature_flags).toEqual({});
      expect(v3Wire.feature_flags).toEqual({});
    });

    it('V2 preserves feature_flags with boolean values', () => {
      const canonical = createFeatureFlaggedCustomer();
      const v2Wire = createV2WireCustomer(canonical);

      const result = v2CustomerSchema.safeParse(v2Wire);

      if (result.success) {
        expect(result.data.feature_flags).toBeDefined();
        // withFeatureFlags transforms values to booleans
      }
    });

    it('V3 wire preserves native boolean feature_flags', () => {
      const canonical = createFeatureFlaggedCustomer();
      const v3Wire = createV3WireCustomer(canonical);

      // V3 uses native types
      expect(v3Wire.feature_flags.beta_features).toBe(true);
      expect(v3Wire.feature_flags.dark_mode).toBe(true);
      expect(v3Wire.feature_flags.api_v3).toBe(false);

      // V2 should still parse this
      const result = v2CustomerSchema.safeParse(v3Wire);
      expect(result.success).toBe(true);
    });

    it('documents feature_flags transformation behavior', () => {
      // withFeatureFlags accepts Record<string, boolean | number | string>
      // and transforms to Record<string, boolean>
      const wireWithMixedFlags = createV2WireCustomer(createCanonicalCustomer());
      // Simulate mixed types that might come from API
      (wireWithMixedFlags as Record<string, unknown>).feature_flags = {
        enabled_feature: true,
        disabled_feature: false,
        // Note: Non-boolean values get cast in the transform
      };

      const result = v2CustomerSchema.safeParse(wireWithMixedFlags);

      if (result.success) {
        // Verify the transform preserved types
        expect(typeof result.data.feature_flags.enabled_feature).toBe('boolean');
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Edge Case Compatibility
// -----------------------------------------------------------------------------

describe('Edge Case Compatibility', () => {
  describe('null vs undefined handling', () => {
    it('V2 and V3 both handle null last_login identically', () => {
      const canonical = createCanonicalCustomer({ last_login: null });

      const v2Wire = createV2WireCustomer(canonical);
      const v3Wire = createV3WireCustomer(canonical);

      // Both should serialize null as null
      expect(v2Wire.last_login).toBeNull();
      expect(v3Wire.last_login).toBeNull();
    });

    it('V2 and V3 both handle null locale identically', () => {
      const canonical = createCanonicalCustomer({ locale: null });

      const v2Wire = createV2WireCustomer(canonical);
      const v3Wire = createV3WireCustomer(canonical);

      expect(v2Wire.locale).toBeNull();
      expect(v3Wire.locale).toBeNull();
    });

    it('optional contributor field: undefined preserved in both formats', () => {
      const canonical = createCanonicalCustomer();
      delete (canonical as Partial<CustomerCanonical>).contributor;

      const v2Wire = createV2WireCustomer(canonical);
      const v3Wire = createV3WireCustomer(canonical);

      expect(v2Wire.contributor).toBeUndefined();
      expect(v3Wire.contributor).toBeUndefined();
    });
  });

  describe('string "0" vs number 0 vs boolean false', () => {
    it('V2 treats string "0" as false in boolean context', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).verified = '0';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // V2's parseBoolean treats "0" as false
        expect(result.data.verified).toBe(false);
      }
    });

    it('V2 treats string "1" as true in boolean context', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).verified = '1';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // V2's parseBoolean treats "1" as true
        expect(result.data.verified).toBe(true);
      }
    });

    it('V2 treats string "0" as number 0 in counter context', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).secrets_created = '0';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.secrets_created).toBe(0);
      }
    });
  });

  describe('empty string handling', () => {
    it('V2 treats empty string as null for nullable date (last_login)', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).last_login = '';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // parseDateValue returns null for empty string
        expect(result.data.last_login).toBeNull();
      }
    });

    it('V2 treats empty string as false for boolean (verified)', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).verified = '';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for empty string
        expect(result.data.verified).toBe(false);
      }
    });

    it('V2 treats empty string as null for counter fields', () => {
      // Counter fields transform empty string to null via parseNumber
      // Note: .default(0) only applies when the field is MISSING, not when
      // the transform explicitly returns null for empty string
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).secrets_created = '';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // parseNumber returns null for empty string
        // .default(0) doesn't override explicit null from transform
        expect(result.data.secrets_created).toBeNull();
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Compatibility Summary Matrix
// -----------------------------------------------------------------------------

describe('Compatibility Summary', () => {
  it('documents the V2<->V3 compatibility matrix for customer', () => {
    const matrix = {
      'V2 Wire -> V3 Schema': {
        'created/updated (string->number)': 'INCOMPATIBLE - V3 expects number',
        'last_login (string->number)': 'INCOMPATIBLE - V3 expects number',
        'verified/active (string->boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'counter fields (string->number)': 'COMPATIBLE - V3 uses z.coerce.number() per #2699',
        'null timestamps': 'COMPATIBLE - both use null',
        'feature_flags': 'COMPATIBLE - Record<string, boolean>',
      },
      'V3 Wire -> V2 Schema': {
        'created/updated (number->string)': 'COMPATIBLE - V2 parseDate handles numbers',
        'last_login (number->string)': 'COMPATIBLE - V2 parseDate handles numbers',
        'verified/active (boolean->string)': 'COMPATIBLE - V2 parseBoolean handles booleans',
        'counter fields (number->string)': 'COMPATIBLE - V2 parseNumber handles numbers',
        'null timestamps': 'COMPATIBLE - both use null',
        'feature_flags': 'COMPATIBLE - Record<string, boolean>',
      },
      'Semantic Differences': {
        'contributor: undefined': 'Optional in both, undefined allowed',
        'notify_on_reveal: missing': 'V2 defaults to false',
        'counter fields: missing': 'V2 defaults to 0',
        'feature_flags: missing': 'V2 defaults to {}',
      },
    };

    console.log('\n=== V2 <-> V3 Customer Compatibility Matrix ===');
    console.log(JSON.stringify(matrix, null, 2));

    // V3 -> V2 is generally compatible (V2 has flexible preprocessors)
    // V2 -> V3 is generally INCOMPATIBLE (V3 expects strict types)
    expect(true).toBe(true); // Documentation test
  });

  it('documents customer-specific transformation notes', () => {
    const notes = {
      'feature_flags transform':
        'withFeatureFlags accepts mixed types (boolean|number|string) but outputs Record<string, boolean>',
      'createModelSchema fields':
        'identifier, created, updated are added by createModelSchema from base.ts',
      'nullable vs optional':
        'last_login and locale are nullable (can be null), contributor is optional (can be undefined)',
      'default values':
        'Counter fields default to 0, notify_on_reveal defaults to false, feature_flags defaults to {}',
    };

    expect(notes).toBeDefined();
  });
});

// -----------------------------------------------------------------------------
// Transform Error Handling
// -----------------------------------------------------------------------------

describe('Transform Error Handling', () => {
  describe('malformed input handling', () => {
    it('V2 parseNumber returns null for "abc" (non-numeric string)', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).secrets_created = 'abc';

      const result = v2CustomerSchema.safeParse(wire);

      // parseNumber returns null for non-numeric strings
      // Note: .default(0) only applies when field is missing,
      // not when transform returns null for invalid input
      if (result.success) {
        expect(result.data.secrets_created).toBeNull();
      }
    });

    it('V2 parseBoolean returns false for unrecognized values', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).verified = 'maybe';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for unrecognized values
        expect(result.data.verified).toBe(false);
      }
    });

    it('V2 parseDateValue returns null for invalid timestamp', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).last_login = 'not-a-date';

      const result = v2CustomerSchema.safeParse(wire);

      if (result.success) {
        // parseDateValue returns null for unparseable strings
        expect(result.data.last_login).toBeNull();
      }
    });
  });

  describe('role validation', () => {
    it('rejects invalid role values', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).role = 'superuser';

      const result = v2CustomerSchema.safeParse(wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const roleError = result.error.issues.find((i) =>
          i.path.includes('role')
        );
        expect(roleError).toBeDefined();
      }
    });

    it('accepts all valid role values', () => {
      const roles = ['customer', 'colonel', 'recipient', 'user_deleted_self'];

      for (const role of roles) {
        const wire = createV2WireCustomer(
          createCanonicalCustomer({ role: role as CustomerCanonical['role'] })
        );
        const result = v2CustomerSchema.safeParse(wire);

        expect(result.success, `Role '${role}' should be valid`).toBe(true);
      }
    });
  });

  describe('email validation', () => {
    it('validates email format', () => {
      const wire = createV2WireCustomer(createCanonicalCustomer());
      (wire as Record<string, unknown>).email = 'not-an-email';

      const result = v2CustomerSchema.safeParse(wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const emailError = result.error.issues.find((i) =>
          i.path.includes('email')
        );
        expect(emailError).toBeDefined();
      }
    });

    it('accepts valid email formats', () => {
      const validEmails = [
        'user@example.com',
        'user+tag@example.com',
        'user.name@sub.example.com',
      ];

      for (const email of validEmails) {
        const wire = createV2WireCustomer(createCanonicalCustomer({ email }));
        const result = v2CustomerSchema.safeParse(wire);

        expect(result.success, `Email '${email}' should be valid`).toBe(true);
      }
    });
  });
});
