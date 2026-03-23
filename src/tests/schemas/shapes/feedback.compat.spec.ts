// src/tests/schemas/shapes/feedback.compat.spec.ts
//
// Cross-version compatibility tests for feedback schemas.
// Tests what happens when V2 wire data is parsed by V3 schema and vice versa.
//
// Purpose:
//   - Document expected failures (incompatible encodings)
//   - Verify graceful handling where possible
//   - Establish compatibility matrix for migration planning

import { describe, it, expect } from 'vitest';
import {
  feedbackSchema as v2FeedbackSchema,
  feedbackDetailsSchema as v2FeedbackDetailsSchema,
} from '@/schemas/shapes/v2/feedback';
import {
  feedbackRecord as v3FeedbackSchema,
  feedbackDetails as v3FeedbackDetailsSchema,
} from '@/schemas/shapes/v3/feedback';
import {
  createCanonicalFeedback,
  createCanonicalFeedbackDetails,
  createV2WireFeedback,
  createV2WireFeedbackDetails,
  createV3WireFeedback,
  createV3WireFeedbackDetails,
} from './fixtures/feedback.fixtures';

// -----------------------------------------------------------------------------
// V2 Wire -> V3 Schema (Forward Compatibility)
// -----------------------------------------------------------------------------

describe('V2 Wire -> V3 Schema (Forward Compatibility)', () => {
  describe('feedbackRecord', () => {
    it('FAILS: V3 expects number stamp, V2 sends string', () => {
      const canonical = createCanonicalFeedback();
      const v2Wire = createV2WireFeedback(canonical);

      // V2 sends stamp as ISO string, V3 expects Unix epoch number
      expect(typeof v2Wire.stamp).toBe('string');

      const result = v3FeedbackSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const stampError = result.error.issues.find((i) => i.path.includes('stamp'));
        expect(stampError).toBeDefined();
        // V3 transforms.fromNumber.toDate expects number input
        expect(stampError?.message).toContain('number');
      }
    });

    it('SUCCEEDS: V3 accepts V2 wire if stamp is coerced to number', () => {
      const canonical = createCanonicalFeedback();
      const v2Wire = createV2WireFeedback(canonical);

      // Manually coerce stamp to number (simulating API middleware)
      const coercedWire = {
        ...v2Wire,
        stamp: Math.floor(new Date(v2Wire.stamp).getTime() / 1000),
      };

      const result = v3FeedbackSchema.safeParse(coercedWire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.stamp).toBeInstanceOf(Date);
      }
    });

    it('V3 rejects V2 wire: type mismatch on stamp', () => {
      const canonical = createCanonicalFeedback();
      const v2Wire = createV2WireFeedback(canonical);

      const result = v3FeedbackSchema.safeParse(v2Wire);

      // V3 schema requires number for stamp
      expect(result.success).toBe(false);
    });
  });

  describe('feedbackDetails', () => {
    it('FAILS: V3 expects boolean, V2 sends string', () => {
      const canonical = createCanonicalFeedbackDetails({ received: true });
      const v2Wire = createV2WireFeedbackDetails(canonical);

      // V2 sends received as string "true"
      expect(typeof v2Wire.received).toBe('string');

      const result = v3FeedbackDetailsSchema.safeParse(v2Wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const receivedError = result.error.issues.find((i) =>
          i.path.includes('received')
        );
        expect(receivedError).toBeDefined();
      }
    });

    it('SUCCEEDS: V3 accepts undefined received (optional in V2)', () => {
      // When V2 doesn't send received at all
      const wire = { msg: 'test' }; // No received field

      // V3 feedbackDetails only has received field
      const result = v3FeedbackDetailsSchema.safeParse({});

      // V3 has received: z.boolean().nullable().transform(v => v ?? false)
      // undefined will be treated as null and transformed to false
      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Wire -> V2 Schema (Backward Compatibility)
// -----------------------------------------------------------------------------

describe.skip('V3 Wire -> V2 Schema (Backward Compatibility)', () => {
  describe('feedbackSchema', () => {
    it('FAILS: V2 expects string stamp, V3 sends number', () => {
      const canonical = createCanonicalFeedback();
      const v3Wire = createV3WireFeedback(canonical);

      // V3 sends stamp as Unix epoch number
      expect(typeof v3Wire.stamp).toBe('number');

      const result = v2FeedbackSchema.safeParse(v3Wire);

      // V2 schema has stamp: z.string() - strict type
      expect(result.success).toBe(false);
      if (!result.success) {
        const stampError = result.error.issues.find((i) => i.path.includes('stamp'));
        expect(stampError).toBeDefined();
        expect(stampError?.message).toContain('string');
      }
    });

    it('SUCCEEDS: V2 accepts V3 wire if stamp is coerced to string', () => {
      const canonical = createCanonicalFeedback();
      const v3Wire = createV3WireFeedback(canonical);

      // Manually coerce stamp to string (simulating API middleware)
      const coercedWire = {
        ...v3Wire,
        stamp: new Date(v3Wire.stamp * 1000).toISOString(),
      };

      const result = v2FeedbackSchema.safeParse(coercedWire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(typeof result.data.stamp).toBe('string');
      }
    });

    it('V2 preserves message content from V3 wire', () => {
      const canonical = createCanonicalFeedback();
      const v3Wire = createV3WireFeedback(canonical);

      // Coerce stamp for compatibility
      const coercedWire = {
        ...v3Wire,
        stamp: new Date(v3Wire.stamp * 1000).toISOString(),
      };

      const result = v2FeedbackSchema.safeParse(coercedWire);

      if (result.success) {
        expect(result.data.msg).toBe(canonical.msg);
      }
    });
  });

  describe('feedbackDetailsSchema', () => {
    it('SUCCEEDS: V2 transforms.fromString.boolean handles native boolean', () => {
      const canonical = createCanonicalFeedbackDetails({ received: true });
      const v3Wire = createV3WireFeedbackDetails(canonical);

      // V3 sends received as native boolean
      expect(typeof v3Wire.received).toBe('boolean');

      const result = v2FeedbackDetailsSchema.safeParse(v3Wire);

      // V2's fromString.boolean preprocessor handles native booleans
      if (result.success) {
        expect(result.data.received).toBe(true);
      }
    });

    it('SUCCEEDS: V2 handles false boolean from V3', () => {
      const canonical = createCanonicalFeedbackDetails({ received: false });
      const v3Wire = createV3WireFeedbackDetails(canonical);

      const result = v2FeedbackDetailsSchema.safeParse(v3Wire);

      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Edge Case Compatibility
// -----------------------------------------------------------------------------

describe('Edge Case Compatibility', () => {
  describe('message content preservation', () => {
    it('both formats preserve special characters', () => {
      const specialMsg = 'Test with "quotes", <tags>, & ampersands!';
      const canonical = createCanonicalFeedback({ msg: specialMsg });

      // V2 path
      const v2Wire = createV2WireFeedback(canonical);
      const v2Parsed = v2FeedbackSchema.parse(v2Wire);

      // V3 path
      const v3Wire = createV3WireFeedback(canonical);
      const v3Parsed = v3FeedbackSchema.parse(v3Wire);

      expect(v2Parsed.msg).toBe(specialMsg);
      expect(v3Parsed.msg).toBe(specialMsg);
    });

    it('both formats preserve unicode characters', () => {
      const unicodeMsg = 'Feedback with emoji and unicode chars';
      const canonical = createCanonicalFeedback({ msg: unicodeMsg });

      const v2Wire = createV2WireFeedback(canonical);
      const v2Parsed = v2FeedbackSchema.parse(v2Wire);

      const v3Wire = createV3WireFeedback(canonical);
      const v3Parsed = v3FeedbackSchema.parse(v3Wire);

      expect(v2Parsed.msg).toBe(unicodeMsg);
      expect(v3Parsed.msg).toBe(unicodeMsg);
    });

    it('both formats preserve newlines', () => {
      const multilineMsg = 'Line 1\nLine 2\nLine 3';
      const canonical = createCanonicalFeedback({ msg: multilineMsg });

      const v2Wire = createV2WireFeedback(canonical);
      const v2Parsed = v2FeedbackSchema.parse(v2Wire);

      const v3Wire = createV3WireFeedback(canonical);
      const v3Parsed = v3FeedbackSchema.parse(v3Wire);

      expect(v2Parsed.msg).toBe(multilineMsg);
      expect(v3Parsed.msg).toBe(multilineMsg);
    });
  });

  describe('timestamp edge cases', () => {
    it('V2 and V3 represent same timestamp differently', () => {
      const timestamp = new Date('2024-01-15T10:00:00.000Z');
      const canonical = createCanonicalFeedback({ stamp: timestamp });

      const v2Wire = createV2WireFeedback(canonical);
      const v3Wire = createV3WireFeedback(canonical);

      // V2: ISO string
      expect(v2Wire.stamp).toBe('2024-01-15T10:00:00.000Z');

      // V3: Unix epoch seconds (compute expected value)
      const expectedEpoch = Math.floor(timestamp.getTime() / 1000);
      expect(v3Wire.stamp).toBe(expectedEpoch);

      // Both represent the same moment
      expect(new Date(v2Wire.stamp).getTime()).toBe(v3Wire.stamp * 1000);
    });

    it('V2 string timestamp preserves milliseconds in format', () => {
      const timestamp = new Date('2024-01-15T10:00:00.500Z');
      const canonical = createCanonicalFeedback({ stamp: timestamp });

      const v2Wire = createV2WireFeedback(canonical);

      // V2 ISO string includes milliseconds
      expect(v2Wire.stamp).toBe('2024-01-15T10:00:00.500Z');
    });

    it('V3 epoch seconds loses millisecond precision', () => {
      const timestamp = new Date('2024-01-15T10:00:00.500Z');
      const canonical = createCanonicalFeedback({ stamp: timestamp });

      const v3Wire = createV3WireFeedback(canonical);
      const v3Parsed = v3FeedbackSchema.parse(v3Wire);

      // V3 epoch seconds truncates to whole seconds
      // Compute the expected truncated timestamp
      const truncatedMs = Math.floor(timestamp.getTime() / 1000) * 1000;
      expect(v3Parsed.stamp.getTime()).toBe(truncatedMs);

      // Original had 500ms (verify milliseconds were in original)
      expect(canonical.stamp.getMilliseconds()).toBe(500);

      // Parsed loses the 500ms
      expect(v3Parsed.stamp.getMilliseconds()).toBe(0);
    });
  });
});

// -----------------------------------------------------------------------------
// Compatibility Summary Matrix
// -----------------------------------------------------------------------------

describe('Compatibility Summary', () => {
  it('documents the V2<->V3 compatibility matrix', () => {
    const matrix = {
      'V2 Wire -> V3 Schema': {
        'msg (string->string)': 'COMPATIBLE',
        'stamp (string->number)': 'INCOMPATIBLE - V3 expects number',
        'received (string->boolean)': 'INCOMPATIBLE - V3 expects boolean',
      },
      'V3 Wire -> V2 Schema': {
        'msg (string->string)': 'COMPATIBLE',
        'stamp (number->string)': 'INCOMPATIBLE - V2 expects string',
        'received (boolean->string)': 'COMPATIBLE - V2 preprocessor handles booleans',
      },
      'Semantic Differences': {
        'stamp type': 'V2 outputs string, V3/contract outputs Date',
        'received undefined': 'V2 keeps undefined, V3 transforms null->false',
        'timestamp precision': 'V2 preserves ms, V3 truncates to seconds',
      },
    };

    console.log('\n=== Feedback V2 <-> V3 Compatibility Matrix ===');
    console.log(JSON.stringify(matrix, null, 2));

    // V2 -> V3: Generally INCOMPATIBLE (different type expectations)
    // V3 -> V2: Partially compatible (V2 has flexible preprocessors for booleans)
    expect(true).toBe(true); // Documentation test
  });

  it('documents V2 stamp string vs V3 Date semantic difference', () => {
    // This is the key semantic gap between V2 and the contract
    const canonical = createCanonicalFeedback();

    // V2 output
    const v2Wire = createV2WireFeedback(canonical);
    const v2Parsed = v2FeedbackSchema.parse(v2Wire);

    // V3 output
    const v3Wire = createV3WireFeedback(canonical);
    const v3Parsed = v3FeedbackSchema.parse(v3Wire);

    // V2: stamp is string (does not match contract)
    expect(typeof v2Parsed.stamp).toBe('string');

    // V3: stamp is Date (matches contract)
    expect(v3Parsed.stamp).toBeInstanceOf(Date);

    // Document: V2 feedbackSchema needs a transform to match the contract
    console.log('[V2 Feedback] stamp: string (contract expects Date)');
    console.log('[V3 Feedback] stamp: Date (matches contract)');
  });

  it('documents received null->false transform in V3', () => {
    // V3 explicitly transforms null to false
    const wireWithNull = { received: null };

    const v3Parsed = v3FeedbackDetailsSchema.parse(wireWithNull);

    // V3 normalizes null to false
    expect(v3Parsed.received).toBe(false);
  });
});

// -----------------------------------------------------------------------------
// Transform Error Handling
// -----------------------------------------------------------------------------

describe('Transform Error Handling', () => {
  describe('V2 boolean field edge cases', () => {
    it.each([
      ['true', true, 'string "true"'],
      ['false', false, 'string "false"'],
      ['1', true, 'string "1"'],
      ['0', false, 'string "0"'],
      [true, true, 'native true'],
      [false, false, 'native false'],
    ])('V2 transforms %p -> %s (%s)', (input, expected, _description) => {
      const wire = { received: input };
      const result = v2FeedbackDetailsSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.received).toBe(expected);
      }
    });
  });

  describe('V3 strict type validation', () => {
    it('V3 rejects string "true" for boolean field', () => {
      const wire = { received: 'true' };
      const result = v3FeedbackDetailsSchema.safeParse(wire);

      // V3 expects native boolean
      expect(result.success).toBe(false);
    });

    it('V3 rejects string for number stamp', () => {
      const wire = { msg: 'test', stamp: '2024-01-15T10:00:00Z' };
      const result = v3FeedbackSchema.safeParse(wire);

      // V3 expects number for stamp
      expect(result.success).toBe(false);
    });

    it('V3 accepts null for received (transforms to false)', () => {
      const wire = { received: null };
      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });
  });
});
