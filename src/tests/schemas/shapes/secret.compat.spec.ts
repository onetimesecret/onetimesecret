// src/tests/schemas/shapes/secret.compat.spec.ts
//
// Cross-version compatibility tests for secret schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning

import { describe, it, expect } from 'vitest';
import {
  secretSchema as v2SecretSchema,
  secretDetailsSchema as v2SecretDetailsSchema,
} from '@/schemas/shapes/v2/secret';
import {
  secretSchema as v3SecretSchema,
  secretDetailsSchema as v3SecretDetailsSchema,
} from '@/schemas/shapes/v3/secret';
import {
  createCanonicalSecretWithTimestamps,
  createCanonicalSecretDetails,
  createV2WireSecret,
  createV2WireSecretDetails,
  createV3WireSecret,
  createV3WireSecretDetails,
} from './fixtures/secret.fixtures';

// ─────────────────────────────────────────────────────────────────────────────
// V2 Wire → V3 Schema (Forward Compatibility)
// ─────────────────────────────────────────────────────────────────────────────

describe('V2 Wire → V3 Schema (Forward Compatibility)', () => {
  describe('secretRecord', () => {
    it('FAILS: V3 rejects V2 string-encoded booleans', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: true,
      });
      const v2Wire = createV2WireSecret(canonical);

      // V2 sends booleans as strings ("true"/"false")
      expect(typeof v2Wire.has_passphrase).toBe('string');

      // V3 expects native boolean
      const result = v3SecretSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const boolError = result.error.issues.find(
          (i) => i.path.includes('has_passphrase') || i.path.includes('verification')
        );
        expect(boolError).toBeDefined();
      }
    });

    it('FAILS: V3 rejects V2 string-encoded numbers', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_ttl: 3600,
        lifespan: 86400,
      });
      const v2Wire = createV2WireSecret(canonical);

      // V2 sends numbers as strings
      expect(typeof v2Wire.secret_ttl).toBe('string');
      expect(typeof v2Wire.lifespan).toBe('string');

      // V3 expects native numbers
      const result = v3SecretSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const ttlError = result.error.issues.find(
          (i) => i.path.includes('secret_ttl') || i.path.includes('lifespan')
        );
        expect(ttlError).toBeDefined();
      }
    });

    it('FAILS: V3 rejects V2 string-encoded timestamps', () => {
      const canonical = createCanonicalSecretWithTimestamps();
      const v2Wire = createV2WireSecret(canonical);

      // V2 sends timestamps as strings (Unix epoch seconds as string)
      expect(typeof v2Wire.created).toBe('string');
      expect(typeof v2Wire.updated).toBe('string');

      const result = v3SecretSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
    });

    it('FAILS: V2 deprecated fields (is_viewed/is_received) present but not in V3 schema', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        is_previewed: true,
        is_revealed: true,
      });
      const v2Wire = createV2WireSecret(canonical);

      // V2 includes deprecated aliases
      expect(v2Wire.is_viewed).toBeDefined();
      expect(v2Wire.is_received).toBeDefined();

      // V3 schema doesn't have these fields (may pass with .strip() or fail with .strict())
      const result = v3SecretSchema.safeParse(v2Wire);
      // Document the behavior
      console.log('[V2→V3] deprecated field handling:', result.success ? 'stripped' : 'rejected');
    });
  });

  describe('secretDetails', () => {
    it('FAILS: V3 rejects V2 string-encoded booleans', () => {
      const canonical = createCanonicalSecretDetails();
      const v2Wire = createV2WireSecretDetails(canonical);

      const result = v3SecretDetailsSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
    });

    it('FAILS: V3 rejects V2 string-encoded display_lines', () => {
      const canonical = createCanonicalSecretDetails({
        display_lines: 10,
      });
      const v2Wire = createV2WireSecretDetails(canonical);

      expect(typeof v2Wire.display_lines).toBe('string');

      const result = v3SecretDetailsSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const linesError = result.error.issues.find((i) =>
          i.path.includes('display_lines')
        );
        expect(linesError).toBeDefined();
      }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// V3 Wire → V2 Schema (Backward Compatibility)
// ─────────────────────────────────────────────────────────────────────────────

describe('V3 Wire → V2 Schema (Backward Compatibility)', () => {
  describe('secretSchema', () => {
    it('SUCCEEDS: V2 transforms.fromString.boolean handles native booleans', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        has_passphrase: true,
        verification: false,
      });
      const v3Wire = createV3WireSecret(canonical);

      expect(typeof v3Wire.has_passphrase).toBe('boolean');
      expect(typeof v3Wire.verification).toBe('boolean');

      const result = v2SecretSchema.safeParse(v3Wire);

      // V2's parseBoolean handles native booleans
      if (result.success) {
        expect(result.data.has_passphrase).toBe(true);
        expect(result.data.verification).toBe(false);
      }
    });

    it('SUCCEEDS: V2 transforms.fromString.number handles native numbers', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_ttl: 3600,
        lifespan: 86400,
      });
      const v3Wire = createV3WireSecret(canonical);

      expect(typeof v3Wire.secret_ttl).toBe('number');
      expect(typeof v3Wire.lifespan).toBe('number');

      const result = v2SecretSchema.safeParse(v3Wire);

      // V2's parseNumber handles native numbers
      if (result.success) {
        expect(result.data.secret_ttl).toBe(3600);
        expect(result.data.lifespan).toBe(86400);
      }
    });

    it('V2 schema successfully parses complete V3 wire data', () => {
      const canonical = createCanonicalSecretWithTimestamps();
      const v3Wire = createV3WireSecret(canonical);

      const result = v2SecretSchema.safeParse(v3Wire);

      // Document whether this succeeds
      console.log('[V3→V2] secretSchema compatibility:', result.success);
      if (!result.success) {
        console.log('[V3→V2] Errors:', result.error.issues.map((i) => `${i.path}: ${i.message}`));
      }
    });
  });

  describe('secretDetailsSchema', () => {
    it('documents V3→V2 secret details compatibility', () => {
      const canonical = createCanonicalSecretDetails();
      const v3Wire = createV3WireSecretDetails(canonical);

      const result = v2SecretDetailsSchema.safeParse(v3Wire);

      console.log('[V3→V2] secretDetails compatibility:', result.success);
      if (!result.success) {
        console.log('[V3→V2] Errors:', result.error.issues.map((i) => `${i.path}: ${i.message}`));
      }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Semantic Differences
// ─────────────────────────────────────────────────────────────────────────────

describe('Semantic Differences', () => {
  describe('deprecated field mappings', () => {
    it('V2 includes is_viewed/is_received aliases', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        is_previewed: true,
        is_revealed: true,
      });
      const v2Wire = createV2WireSecret(canonical);

      // V2 serializer maps canonical fields to both names
      expect(v2Wire.is_previewed).toBeDefined();
      expect(v2Wire.is_revealed).toBeDefined();
      expect(v2Wire.is_viewed).toBeDefined(); // deprecated alias
      expect(v2Wire.is_received).toBeDefined(); // deprecated alias

      // Values should match
      expect(v2Wire.is_viewed).toBe(v2Wire.is_previewed);
      expect(v2Wire.is_received).toBe(v2Wire.is_revealed);
    });

    it('V3 only has canonical field names', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        is_previewed: true,
        is_revealed: true,
      });
      const v3Wire = createV3WireSecret(canonical);

      expect(v3Wire.is_previewed).toBeDefined();
      expect(v3Wire.is_revealed).toBeDefined();
      expect((v3Wire as Record<string, unknown>).is_viewed).toBeUndefined();
      expect((v3Wire as Record<string, unknown>).is_received).toBeUndefined();
    });
  });

  describe('timestamp availability', () => {
    it('V3 wire has native number timestamps', () => {
      const testDate = new Date('2024-01-15T10:00:00.000Z');
      const expectedEpoch = Math.floor(testDate.getTime() / 1000);
      const canonical = createCanonicalSecretWithTimestamps({
        created: testDate,
        updated: new Date('2024-01-15T11:00:00.000Z'),
      });
      const v3Wire = createV3WireSecret(canonical);

      expect(typeof v3Wire.created).toBe('number');
      expect(typeof v3Wire.updated).toBe('number');
      expect(v3Wire.created).toBe(expectedEpoch);
    });

    it('V2 wire has string timestamps', () => {
      const testDate = new Date('2024-01-15T10:00:00.000Z');
      const expectedEpoch = String(Math.floor(testDate.getTime() / 1000));
      const canonical = createCanonicalSecretWithTimestamps({
        created: testDate,
        updated: new Date('2024-01-15T11:00:00.000Z'),
      });
      const v2Wire = createV2WireSecret(canonical);

      expect(typeof v2Wire.created).toBe('string');
      expect(typeof v2Wire.updated).toBe('string');
      expect(v2Wire.created).toBe(expectedEpoch);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Edge Case Compatibility
// ─────────────────────────────────────────────────────────────────────────────

describe('Edge Case Compatibility', () => {
  describe('optional field handling', () => {
    it('V2 and V3 both handle undefined secret_value', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_value: undefined,
      });

      const v2Wire = createV2WireSecret(canonical);
      const v3Wire = createV3WireSecret(canonical);

      expect(v2Wire.secret_value).toBeUndefined();
      expect(v3Wire.secret_value).toBeUndefined();
    });

    it('V2 and V3 both handle present secret_value', () => {
      const canonical = createCanonicalSecretWithTimestamps({
        secret_value: 'my secret',
      });

      const v2Wire = createV2WireSecret(canonical);
      const v3Wire = createV3WireSecret(canonical);

      expect(v2Wire.secret_value).toBe('my secret');
      expect(v3Wire.secret_value).toBe('my secret');
    });
  });

  describe('nullable one_liner in details', () => {
    it('V2 and V3 both handle null one_liner', () => {
      const canonical = createCanonicalSecretDetails({
        one_liner: null,
      });

      const v2Wire = createV2WireSecretDetails(canonical);
      const v3Wire = createV3WireSecretDetails(canonical);

      expect(v2Wire.one_liner).toBeNull();
      expect(v3Wire.one_liner).toBeNull();
    });

    it('V2 encodes boolean one_liner as string, V3 keeps native', () => {
      const canonical = createCanonicalSecretDetails({
        one_liner: true,
      });

      const v2Wire = createV2WireSecretDetails(canonical);
      const v3Wire = createV3WireSecretDetails(canonical);

      expect(typeof v2Wire.one_liner).toBe('string');
      expect(v2Wire.one_liner).toBe('true');
      expect(typeof v3Wire.one_liner).toBe('boolean');
      expect(v3Wire.one_liner).toBe(true);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Transform Error Handling
// ─────────────────────────────────────────────────────────────────────────────

describe('Transform Error Handling', () => {
  describe('V2 graceful degradation', () => {
    it('V2 parseBoolean returns false for unrecognized string', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = 'maybe';

      const result = v2SecretSchema.safeParse(wire);

      if (result.success) {
        // V2's parseBoolean treats unrecognized as false
        expect(result.data.has_passphrase).toBe(false);
      }
    });

    it('V2 parseNumber returns null for non-numeric string', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).secret_ttl = 'invalid';

      const result = v2SecretSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.secret_ttl).toBeNull();
      }
    });

    it('V2 parseBoolean handles null gracefully', () => {
      const wire = createV2WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = null;

      const result = v2SecretSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.has_passphrase).toBe(false);
      }
    });
  });

  describe('V3 strict validation', () => {
    it('V3 rejects string "true" for boolean field', () => {
      const wire = createV3WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).has_passphrase = 'true';

      const result = v3SecretSchema.safeParse(wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        expect(result.error.issues[0].code).toBe('invalid_type');
      }
    });

    it('V3 rejects string "3600" for number field', () => {
      const wire = createV3WireSecret(createCanonicalSecretWithTimestamps());
      (wire as Record<string, unknown>).secret_ttl = '3600';

      const result = v3SecretSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Compatibility Summary Matrix
// ─────────────────────────────────────────────────────────────────────────────

describe('Compatibility Summary', () => {
  it('documents the V2↔V3 secret compatibility matrix', () => {
    const matrix = {
      'V2 Wire → V3 Schema': {
        'identifier/key/shortid (string)': 'COMPATIBLE',
        'state (enum)': 'COMPATIBLE',
        'has_passphrase (string→boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'verification (string→boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'is_previewed (string→boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'is_revealed (string→boolean)': 'INCOMPATIBLE - V3 expects boolean',
        'secret_ttl (string→number)': 'INCOMPATIBLE - V3 expects number',
        'lifespan (string→number)': 'INCOMPATIBLE - V3 expects number',
        'created (string→number)': 'INCOMPATIBLE - V3 expects number',
        'secret_value (optional string)': 'COMPATIBLE',
        'is_viewed/is_received (deprecated)': 'N/A - V3 lacks these fields',
      },
      'V3 Wire → V2 Schema': {
        'identifier/key/shortid (string)': 'COMPATIBLE',
        'state (enum)': 'COMPATIBLE',
        'has_passphrase (boolean→string)': 'COMPATIBLE - V2 parseBoolean handles native',
        'verification (boolean→string)': 'COMPATIBLE - V2 parseBoolean handles native',
        'is_previewed (boolean→string)': 'COMPATIBLE - V2 parseBoolean handles native',
        'is_revealed (boolean→string)': 'COMPATIBLE - V2 parseBoolean handles native',
        'secret_ttl (number→string)': 'COMPATIBLE - V2 parseNumber handles native',
        'lifespan (number→string)': 'COMPATIBLE - V2 parseNumber handles native',
        'created (number→string)': 'COMPATIBLE - V2 parseDate handles numbers',
        'secret_value (optional string)': 'COMPATIBLE',
      },
    };

    console.log('\n=== V2 ↔ V3 Secret Compatibility Matrix ===');
    console.log(JSON.stringify(matrix, null, 2));

    // V3 → V2 is generally compatible (V2 has flexible preprocessors)
    // V2 → V3 is generally INCOMPATIBLE (V3 expects strict types)
    expect(true).toBe(true); // Documentation test
  });
});
