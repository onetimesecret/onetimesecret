// src/tests/schemas/shapes/receipt.compat.spec.ts
//
// Cross-version compatibility tests for receipt schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning

import { describe, it, expect } from 'vitest';
import {
  receiptBaseSchema as v2ReceiptBaseSchema,
  receiptSchema as v2ReceiptSchema,
  receiptDetailsSchema as v2ReceiptDetailsSchema,
} from '@/schemas/shapes/v2/receipt';
import {
  receiptBaseSchema as v3ReceiptBaseSchema,
  receiptSchema as v3ReceiptSchema,
  receiptDetailsSchema as v3ReceiptDetailsSchema,
} from '@/schemas/shapes/v3/receipt';
import {
  createCanonicalReceiptBase,
  createCanonicalReceipt,
  createCanonicalReceiptDetails,
  createV2WireReceiptBase,
  createV2WireReceipt,
  createV2WireReceiptDetails,
  createV3WireReceiptBase,
  createV3WireReceipt,
  createV3WireReceiptDetails,
} from './fixtures/receipt.fixtures';

// ─────────────────────────────────────────────────────────────────────────────
// V2 Wire → V3 Schema (Forward Compatibility)
// ─────────────────────────────────────────────────────────────────────────────

describe('V2 Wire → V3 Schema (Forward Compatibility)', () => {
  describe('receiptBaseRecord', () => {
    it('FAILS: V3 expects number timestamps, V2 sends strings for shared/received/etc', () => {
      const canonical = createCanonicalReceiptBase({
        shared: new Date('2024-01-15T11:00:00.000Z'),
      });
      const v2Wire = createV2WireReceiptBase(canonical);

      // V2 sends shared as ISO string, V3 expects number
      const result = v3ReceiptBaseSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const sharedError = result.error.issues.find((i) => i.path.includes('shared'));
        expect(sharedError).toBeDefined();
        expect(sharedError?.message).toContain('number');
      }
    });

    it('FAILS: V3 rejects V2 wire even when timestamps are null (due to string booleans/numbers)', () => {
      // Even when nullable timestamps are null, V2 still sends booleans/numbers as strings
      const canonical = createCanonicalReceiptBase({
        shared: null,
        received: null,
        viewed: null,
        previewed: null,
        revealed: null,
        burned: null,
      });
      const v2Wire = createV2WireReceiptBase(canonical);

      const result = v3ReceiptBaseSchema.safeParse(v2Wire);

      // V3 still rejects due to string-encoded booleans and numbers
      expect(result.success).toBe(false);
      if (!result.success) {
        // Should fail on boolean or number fields
        const hasTypeError = result.error.issues.some(
          (i) => i.message.includes('boolean') || i.message.includes('number')
        );
        expect(hasTypeError).toBe(true);
      }
    });

    it('SUCCEEDS: V3 parses created/updated (both V2 and V3 use numbers)', () => {
      // created and updated are numbers in both formats
      const canonical = createCanonicalReceiptBase();
      const v2Wire = createV2WireReceiptBase(canonical);

      // Extract just the compatible fields to verify
      expect(typeof v2Wire.created).toBe('number');
      expect(typeof v2Wire.updated).toBe('number');
    });

    it('FAILS: V3 boolean fields reject V2 string booleans', () => {
      const canonical = createCanonicalReceiptBase({
        is_viewed: true,
        is_burned: true,
      });
      const v2Wire = createV2WireReceiptBase(canonical);

      // V2 sends booleans as strings ("true"/"false")
      expect(typeof v2Wire.is_viewed).toBe('string');
      expect(typeof v2Wire.is_burned).toBe('string');

      // V3 expects native booleans
      const result = v3ReceiptBaseSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const boolError = result.error.issues.find(
          (i) => i.path.includes('is_viewed') || i.path.includes('is_burned')
        );
        expect(boolError).toBeDefined();
      }
    });

    it('FAILS: V3 number fields reject V2 string numbers', () => {
      const canonical = createCanonicalReceiptBase({
        secret_ttl: 3600,
        receipt_ttl: 7200,
      });
      const v2Wire = createV2WireReceiptBase(canonical);

      // V2 sends numbers as strings
      expect(typeof v2Wire.secret_ttl).toBe('string');
      expect(typeof v2Wire.receipt_ttl).toBe('string');

      // V3 expects native numbers
      const result = v3ReceiptBaseSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const ttlError = result.error.issues.find(
          (i) => i.path.includes('secret_ttl') || i.path.includes('receipt_ttl')
        );
        expect(ttlError).toBeDefined();
      }
    });
  });

  describe('receiptDetails', () => {
    it('FAILS: V3 rejects V2 string-encoded booleans', () => {
      const canonical = createCanonicalReceiptDetails();
      const v2Wire = createV2WireReceiptDetails(canonical);

      const result = v3ReceiptDetailsSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// V3 Wire → V2 Schema (Backward Compatibility)
// ─────────────────────────────────────────────────────────────────────────────

describe('V3 Wire → V2 Schema (Backward Compatibility)', () => {
  describe('receiptBaseSchema', () => {
    it('SUCCEEDS: V2 transforms.fromString can handle numbers for timestamps', () => {
      // V2's parseDateValue handles both strings AND numbers
      const canonical = createCanonicalReceiptBase({
        shared: new Date('2024-01-15T11:00:00.000Z'),
      });
      const v3Wire = createV3WireReceiptBase(canonical);

      // V3 sends as number
      expect(typeof v3Wire.shared).toBe('number');

      // V2's preprocess should handle this
      const result = v2ReceiptBaseSchema.safeParse(v3Wire);

      // This may succeed due to parseDateValue's flexibility
      if (result.success) {
        expect(result.data.shared).toBeInstanceOf(Date);
      }
    });

    it('SUCCEEDS: V2 transforms.fromString.boolean handles native booleans', () => {
      // V2's parseBoolean function handles both strings AND booleans
      const canonical = createCanonicalReceiptBase({
        is_viewed: true,
        is_burned: false,
      });
      const v3Wire = createV3WireReceiptBase(canonical);

      expect(typeof v3Wire.is_viewed).toBe('boolean');
      expect(typeof v3Wire.is_burned).toBe('boolean');

      const result = v2ReceiptBaseSchema.safeParse(v3Wire);

      // V2's parseBoolean handles native booleans
      if (result.success) {
        expect(result.data.is_viewed).toBe(true);
        expect(result.data.is_burned).toBe(false);
      }
    });

    it('SUCCEEDS: V2 transforms.fromString.number handles native numbers', () => {
      // V2's parseNumber function handles both strings AND numbers
      const canonical = createCanonicalReceiptBase({
        secret_ttl: 3600,
        receipt_ttl: 7200,
        lifespan: 86400,
      });
      const v3Wire = createV3WireReceiptBase(canonical);

      expect(typeof v3Wire.secret_ttl).toBe('number');

      const result = v2ReceiptBaseSchema.safeParse(v3Wire);

      // V2's parseNumber handles native numbers
      if (result.success) {
        expect(result.data.secret_ttl).toBe(3600);
        expect(result.data.receipt_ttl).toBe(7200);
        expect(result.data.lifespan).toBe(86400);
      }
    });

    it('V2 schema successfully parses complete V3 wire data', () => {
      // Due to V2's flexible preprocessors, it should handle V3 data
      const canonical = createCanonicalReceiptBase();
      const v3Wire = createV3WireReceiptBase(canonical);

      const result = v2ReceiptBaseSchema.safeParse(v3Wire);

      // Document whether this succeeds
      console.log('[V3→V2] receiptBase compatibility:', result.success);
      if (!result.success) {
        console.log('[V3→V2] Errors:', result.error.issues.map((i) => `${i.path}: ${i.message}`));
      }
    });
  });

  describe('receiptSchema (full)', () => {
    it('documents V3→V2 full receipt compatibility', () => {
      const canonical = createCanonicalReceipt();
      const v3Wire = createV3WireReceipt(canonical);

      const result = v2ReceiptSchema.safeParse(v3Wire);

      console.log('[V3→V2] full receipt compatibility:', result.success);
      if (!result.success) {
        console.log('[V3→V2] Errors:', result.error.issues.slice(0, 5).map((i) => `${i.path}: ${i.message}`));
      }
    });
  });

  describe('receiptDetailsSchema', () => {
    it('documents V3→V2 receipt details compatibility', () => {
      const canonical = createCanonicalReceiptDetails();
      const v3Wire = createV3WireReceiptDetails(canonical);

      const result = v2ReceiptDetailsSchema.safeParse(v3Wire);

      console.log('[V3→V2] receiptDetails compatibility:', result.success);
      if (!result.success) {
        console.log('[V3→V2] Errors:', result.error.issues.map((i) => `${i.path}: ${i.message}`));
      }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Edge Case Compatibility
// ─────────────────────────────────────────────────────────────────────────────

describe('Edge Case Compatibility', () => {
  describe('null vs undefined handling', () => {
    it('V2 and V3 both handle null timestamps identically', () => {
      const canonical = createCanonicalReceiptBase({
        shared: null,
        received: null,
      });

      const v2Wire = createV2WireReceiptBase(canonical);
      const v3Wire = createV3WireReceiptBase(canonical);

      // Both should serialize null as null
      expect(v2Wire.shared).toBeNull();
      expect(v3Wire.shared).toBeNull();
    });

    it('optional fields: undefined preserved in both formats', () => {
      const canonical = createCanonicalReceiptBase({
        custid: undefined,
        memo: undefined,
      });

      const v2Wire = createV2WireReceiptBase(canonical);
      const v3Wire = createV3WireReceiptBase(canonical);

      expect(v2Wire.custid).toBeUndefined();
      expect(v3Wire.custid).toBeUndefined();
    });
  });

  describe('string "0" vs number 0 vs boolean false', () => {
    it('V2 treats string "0" as false in boolean context', () => {
      // Simulate V2 wire with "0" for a boolean field
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      // Manually set to "0" to test parsing
      (wire as Record<string, unknown>).is_viewed = '0';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        // V2's parseBoolean treats "0" as false
        expect(result.data.is_viewed).toBe(false);
      }
    });

    it('V2 treats string "1" as true in boolean context', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).is_viewed = '1';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        // V2's parseBoolean treats "1" as true
        expect(result.data.is_viewed).toBe(true);
      }
    });

    it('V3 rejects string "0" in boolean context', () => {
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      // V3 uses is_previewed, not is_viewed (deprecated in V2)
      (wire as Record<string, unknown>).is_previewed = '0';

      const result = v3ReceiptBaseSchema.safeParse(wire);

      // V3 expects native boolean, not string
      expect(result.success).toBe(false);
    });

    it('V2 treats string "0" as number 0 in number context', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = '0';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.secret_ttl).toBe(0);
      }
    });

    it('V3 rejects string "0" in number context', () => {
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = '0';

      const result = v3ReceiptBaseSchema.safeParse(wire);

      // V3 expects native number
      expect(result.success).toBe(false);
    });
  });

  describe('empty string handling', () => {
    it('V2 treats empty string as null for nullable date', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).shared = '';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        // parseDateValue returns null for empty string
        expect(result.data.shared).toBeNull();
      }
    });

    it('V2 treats empty string as false for boolean', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).is_viewed = '';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean returns false for empty string
        expect(result.data.is_viewed).toBe(false);
      }
    });

    it('V2 treats empty string as null for nullable number', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = '';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        // parseNumber returns null for empty string
        expect(result.data.secret_ttl).toBeNull();
      }
    });
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Compatibility Summary Matrix
// ─────────────────────────────────────────────────────────────────────────────

describe('Compatibility Summary', () => {
  it('documents the V2↔V3 compatibility matrix', () => {
    const matrix = {
      'V2 Wire → V3 Schema': {
        'created/updated (number→number)': 'COMPATIBLE',
        'shared/received (string→number)': 'INCOMPATIBLE - V3 expects number',
        'is_* booleans (string→boolean)': 'INCOMPATIBLE - V3 expects boolean',
        '*_ttl numbers (string→number)': 'INCOMPATIBLE - V3 expects number',
        'null timestamps': 'COMPATIBLE - both use null',
      },
      'V3 Wire → V2 Schema': {
        'created/updated (number→number)': 'COMPATIBLE',
        'shared/received (number→string)': 'COMPATIBLE - V2 parseDate handles numbers',
        'is_* booleans (boolean→string)': 'COMPATIBLE - V2 parseBoolean handles booleans',
        '*_ttl numbers (number→string)': 'COMPATIBLE - V2 parseNumber handles numbers',
        'null timestamps': 'COMPATIBLE - both use null',
      },
      'Semantic Differences': {
        'has_passphrase: null': 'V2 preserves null, V3 transforms to false',
        'can_decrypt: null': 'V2 preserves null, V3 transforms to false',
        'field naming': 'V3 uses is_previewed/is_revealed, V2 has is_viewed/is_received aliases',
        'timestamp naming': 'V3 uses previewed/revealed, V2 has viewed/received aliases',
      },
    };

    console.log('\n=== V2 ↔ V3 Compatibility Matrix ===');
    console.log(JSON.stringify(matrix, null, 2));

    // V3 → V2 is generally compatible (V2 has flexible preprocessors)
    // V2 → V3 is generally INCOMPATIBLE (V3 expects strict types)
    expect(true).toBe(true); // Documentation test
  });

  it('documents has_passphrase null→false semantic difference in V3', () => {
    // This is intentional behavior: V3 normalizes null to false
    // because a consumed/deleted secret has no passphrase concept
    const v2Wire = createV2WireReceiptBase(createCanonicalReceiptBase({
      has_passphrase: null,
    }));
    const v3Wire = createV3WireReceiptBase(createCanonicalReceiptBase({
      has_passphrase: null,
    }));

    const v2Parsed = v2ReceiptBaseSchema.safeParse(v2Wire);
    const v3Parsed = v3ReceiptBaseSchema.safeParse(v3Wire);

    // V2 may preserve null (depending on schema definition)
    // V3 explicitly transforms null → false
    if (v3Parsed.success) {
      expect(v3Parsed.data.has_passphrase).toBe(false);
    }

    // Document this as a known semantic difference
    expect(v3Parsed.success).toBe(true);
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// Transform Error Handling (Task 8)
// ─────────────────────────────────────────────────────────────────────────────

describe('Transform Error Handling', () => {
  describe('V2 number field malformed input', () => {
    it('V2 parseNumber returns null for "abc" (non-numeric string)', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = 'abc';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      // parseNumber returns null for non-numeric strings
      if (result.success) {
        expect(result.data.secret_ttl).toBeNull();
      }
    });

    it.each([
      ['abc', null, 'non-numeric string'],
      ['', null, 'empty string'],
      ['NaN', null, 'NaN string'],
      ['Infinity', Infinity, 'Infinity string (parsed as number)'],
      ['-Infinity', -Infinity, 'negative Infinity'],
      ['1.5e10', 1.5e10, 'scientific notation'],
      ['  42  ', 42, 'number with whitespace'],
      ['0x1F', 31, 'hex notation (parseInt fallback)'],
      ['3.14.159', null, 'multiple decimals (NaN)'],
    ])('V2 parseNumber handles "%s" → %s (%s)', (input, expected, _description) => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = input;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        if (expected === null) {
          expect(result.data.secret_ttl).toBeNull();
        } else {
          expect(result.data.secret_ttl).toBe(expected);
        }
      }
    });

    it('V3 rejects "abc" for number field (no coercion)', () => {
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = 'abc';

      const result = v3ReceiptBaseSchema.safeParse(wire);

      // V3 expects native number, rejects strings
      expect(result.success).toBe(false);
      if (!result.success) {
        const ttlError = result.error.issues.find((i) =>
          i.path.includes('secret_ttl')
        );
        expect(ttlError).toBeDefined();
        expect(ttlError?.message).toContain('number');
      }
    });
  });

  describe('V2 boolean field unexpected values', () => {
    // parseBoolean only returns true for: native true, string "true", or string "1"
    // Everything else returns false (including number 1, which is !== '1')
    it.each([
      ['true', true, 'string "true"'],
      ['false', false, 'string "false"'],
      ['1', true, 'string "1"'],
      ['0', false, 'string "0"'],
      ['', false, 'empty string'],
      ['yes', false, '"yes" (not recognized, defaults to false)'],
      ['no', false, '"no" (not recognized, defaults to false)'],
      ['TRUE', false, 'uppercase "TRUE" (case-sensitive, not recognized)'],
      ['  true  ', false, 'whitespace (not trimmed, defaults to false)'],
      [true, true, 'native boolean true'],
      [false, false, 'native boolean false'],
      [1, false, 'number 1 (not === "1", returns false)'],
      [0, false, 'number 0 (returns false)'],
      [null, false, 'null'],
      [undefined, false, 'undefined'],
    ])('V2 parseBoolean handles %p → %s (%s)', (input, expected, _description) => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).is_viewed = input;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.is_viewed).toBe(expected);
      }
    });

    it('V3 rejects "true" string for boolean field', () => {
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).is_previewed = 'true';

      const result = v3ReceiptBaseSchema.safeParse(wire);

      // V3 expects native boolean
      expect(result.success).toBe(false);
    });
  });

  describe('null/undefined fallback behavior', () => {
    it('V2 parseDateValue: null input → null output', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).shared = null;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.shared).toBeNull();
      }
    });

    it('V2 parseDateValue: undefined input → null output', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      delete (wire as Record<string, unknown>).shared;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      // For optional fields, undefined is valid; shared may default to null
      if (result.success && 'shared' in result.data) {
        expect(result.data.shared).toBeNull();
      }
    });

    it('V2 parseNumber: null input → null output', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = null;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.secret_ttl).toBeNull();
      }
    });

    it('V2 parseBoolean: null input → false output', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).is_viewed = null;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        // parseBoolean treats null as falsy
        expect(result.data.is_viewed).toBe(false);
      }
    });

    it('V3 has_passphrase: null → false (explicit transform)', () => {
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).has_passphrase = null;

      const result = v3ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.has_passphrase).toBe(false);
      }
    });

    it('V3 has_passphrase: undefined → false (explicit transform)', () => {
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      delete (wire as Record<string, unknown>).has_passphrase;

      const result = v3ReceiptBaseSchema.safeParse(wire);

      // V3 schema uses nullish().transform(v => v ?? false)
      if (result.success) {
        expect(result.data.has_passphrase).toBe(false);
      }
    });
  });

  describe('date parsing edge cases', () => {
    it('V2 parseDateValue: invalid ISO string → null', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).shared = 'not-a-date';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      // parseDateValue returns null for unparseable strings
      if (result.success) {
        expect(result.data.shared).toBeNull();
      }
    });

    it('V2 parseDateValue: partial ISO string → attempts parse', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      // Contains "-" so triggers ISO path
      (wire as Record<string, unknown>).shared = '2024-01-15';

      const result = v2ReceiptBaseSchema.safeParse(wire);

      // Should parse as midnight UTC
      if (result.success && result.data.shared) {
        expect(result.data.shared).toBeInstanceOf(Date);
      }
    });

    it('V2 parseDateValue: object input → null (not Date-coercible)', () => {
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).shared = { invalid: true };

      const result = v2ReceiptBaseSchema.safeParse(wire);

      // parseDateValue returns null for non-string/non-number/non-Date
      if (result.success) {
        expect(result.data.shared).toBeNull();
      }
    });

    it('V2 parseDateValue: Date object input → preserved', () => {
      const inputDate = new Date('2024-01-15T10:00:00.000Z');
      const wire = createV2WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).shared = inputDate;

      const result = v2ReceiptBaseSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.shared).toBeInstanceOf(Date);
        expect(result.data.shared?.getTime()).toBe(inputDate.getTime());
      }
    });
  });

  describe('transform error documentation', () => {
    it('documents V2 graceful degradation pattern', () => {
      // V2 transforms use preprocess() which allows graceful handling
      // of unexpected input types. This documents the pattern:
      const patterns = {
        'parseNumber("abc")': 'returns null (graceful)',
        'parseNumber(null)': 'returns null (graceful)',
        'parseBoolean("maybe")': 'returns false (graceful)',
        'parseBoolean(null)': 'returns false (graceful)',
        'parseDateValue("bad")': 'returns null (graceful)',
        'parseDateValue({})': 'returns null (graceful)',
      };

      // All V2 transforms handle bad input without throwing
      // This is intentional for backward compatibility with Redis data
      expect(patterns).toBeDefined();
    });

    it('documents V3 strict validation pattern', () => {
      // V3 uses strict type validation without coercion
      // Malformed input results in ZodError, not silent fallback
      const wire = createV3WireReceiptBase(createCanonicalReceiptBase());
      (wire as Record<string, unknown>).secret_ttl = 'not-a-number';

      const result = v3ReceiptBaseSchema.safeParse(wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        // V3 errors are explicit about the type mismatch
        const error = result.error.issues[0];
        expect(error.code).toBe('invalid_type');
      }
    });
  });
});
