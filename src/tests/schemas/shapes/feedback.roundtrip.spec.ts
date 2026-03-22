// src/tests/schemas/shapes/feedback.roundtrip.spec.ts
//
// Round-trip tests for feedback schemas.
// Verifies: canonical -> wire format -> schema parse -> canonical (equality)
//
// These tests catch transforms that lose information during the parse cycle.
//
// Note: V2 feedbackSchema does NOT transform stamp (outputs string, not Date).
// The contract expects Date, so V2 round-trip will show a semantic difference.
// V3 properly transforms stamp (number -> Date) and matches the contract.

import { describe, it, expect } from 'vitest';
import {
  feedbackSchema as v2FeedbackSchema,
  feedbackDetailsSchema as v2FeedbackDetailsSchema,
} from '@/schemas/shapes/v2/feedback';
import {
  feedbackRecord as v3FeedbackRecord,
  feedbackDetails as v3FeedbackDetailsSchema,
} from '@/schemas/shapes/v3/feedback';
import {
  createCanonicalFeedback,
  createCanonicalFeedbackDetails,
  createMaxLengthFeedback,
  createMinLengthFeedback,
  createReceivedFeedbackDetails,
  createV2WireFeedback,
  createV2WireFeedbackDetails,
  createV3WireFeedback,
  createV3WireFeedbackDetails,
  compareCanonicalFeedback,
  compareCanonicalFeedbackDetails,
} from './fixtures/feedback.fixtures';

// -----------------------------------------------------------------------------
// Test Helpers
// -----------------------------------------------------------------------------

/**
 * Asserts that two dates are equal by timestamp.
 */
function expectDatesEqual(actual: Date | null, expected: Date | null, fieldName: string) {
  if (expected === null) {
    expect(actual, `${fieldName} should be null`).toBeNull();
  } else {
    expect(actual, `${fieldName} should be a Date`).toBeInstanceOf(Date);
    expect(actual!.getTime(), `${fieldName} timestamp mismatch`).toBe(expected.getTime());
  }
}

// -----------------------------------------------------------------------------
// V2 Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V2 Feedback Round-Trip', () => {
  describe('feedbackSchema', () => {
    it('parses feedback wire format successfully', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV2WireFeedback(canonical);
      const result = v2FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.msg).toBe(canonical.msg);
        // V2 keeps stamp as string (no transform)
        expect(typeof result.data.stamp).toBe('string');
      }
    });

    it('documents V2 stamp type mismatch with contract', () => {
      // V2 feedbackSchema has stamp: z.string() with no transform
      // Contract feedbackCanonical has stamp: z.date()
      // This is a known semantic difference
      const canonical = createCanonicalFeedback();
      const wire = createV2WireFeedback(canonical);
      const parsed = v2FeedbackSchema.parse(wire);

      // V2 outputs string, contract expects Date
      expect(typeof parsed.stamp).toBe('string');
      expect(canonical.stamp).toBeInstanceOf(Date);

      // Document this as a known semantic gap
      console.log('[V2 Feedback] stamp type: string (contract expects Date)');
    });

    it('preserves message content through round-trip', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV2WireFeedback(canonical);
      const parsed = v2FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
    });

    it('handles maximum length message', () => {
      const canonical = createMaxLengthFeedback();
      const wire = createV2WireFeedback(canonical);
      const parsed = v2FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
      expect(parsed.msg.length).toBe(1500);
    });

    it('handles minimum length message', () => {
      const canonical = createMinLengthFeedback();
      const wire = createV2WireFeedback(canonical);
      const parsed = v2FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
      expect(parsed.msg.length).toBe(1);
    });

    it('rejects empty message', () => {
      const wire = { msg: '', stamp: '2024-01-15T10:00:00Z' };
      const result = v2FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('rejects message exceeding max length', () => {
      const wire = { msg: 'A'.repeat(1501), stamp: '2024-01-15T10:00:00Z' };
      const result = v2FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });
  });

  describe('feedbackDetailsSchema', () => {
    it('round-trips feedback details with received=false', () => {
      const canonical = createCanonicalFeedbackDetails();
      const wire = createV2WireFeedbackDetails(canonical);
      const parsed = v2FeedbackDetailsSchema.parse(wire);

      // V2 transforms string "false" -> boolean false
      expect(parsed.received).toBe(false);
    });

    it('round-trips feedback details with received=true', () => {
      const canonical = createReceivedFeedbackDetails();
      const wire = createV2WireFeedbackDetails(canonical);
      const parsed = v2FeedbackDetailsSchema.parse(wire);

      // V2 transforms string "true" -> boolean true
      expect(parsed.received).toBe(true);
    });

    it('handles undefined received', () => {
      const wire = {};
      const parsed = v2FeedbackDetailsSchema.parse(wire);

      // Optional field defaults to undefined
      expect(parsed.received).toBeUndefined();
    });

    it('transforms string "true" to boolean true', () => {
      const wire = { received: 'true' };
      const parsed = v2FeedbackDetailsSchema.parse(wire);

      expect(parsed.received).toBe(true);
    });

    it('transforms string "false" to boolean false', () => {
      const wire = { received: 'false' };
      const parsed = v2FeedbackDetailsSchema.parse(wire);

      expect(parsed.received).toBe(false);
    });
  });
});

// -----------------------------------------------------------------------------
// V3 Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V3 Feedback Round-Trip', () => {
  describe('feedbackRecord', () => {
    it('round-trips feedback with Date stamp', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackRecord.parse(wire);

      // V3 transforms number -> Date
      expect(parsed.msg).toBe(canonical.msg);
      expectDatesEqual(parsed.stamp, canonical.stamp, 'stamp');
    });

    it('matches canonical type (stamp is Date)', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackRecord.parse(wire);

      // V3 output matches contract expectation
      expect(parsed.stamp).toBeInstanceOf(Date);
      expect(parsed.stamp.getTime()).toBe(canonical.stamp.getTime());
    });

    it('preserves message content through round-trip', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackRecord.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
    });

    it('handles maximum length message', () => {
      const canonical = createMaxLengthFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackRecord.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
      expect(parsed.msg.length).toBe(1500);
    });

    it('handles minimum length message', () => {
      const canonical = createMinLengthFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackRecord.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
      expect(parsed.msg.length).toBe(1);
    });

    it('verifies V3 complete round-trip equality', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackRecord.parse(wire);

      const result = compareCanonicalFeedback(canonical, parsed);

      expect(result.equal, `Differences: ${result.differences.join(', ')}`).toBe(true);
    });
  });

  describe('feedbackDetails', () => {
    it('round-trips feedback details with received=false', () => {
      const canonical = createCanonicalFeedbackDetails();
      const wire = createV3WireFeedbackDetails(canonical);
      const parsed = v3FeedbackDetailsSchema.parse(wire);

      expect(parsed.received).toBe(false);
    });

    it('round-trips feedback details with received=true', () => {
      const canonical = createReceivedFeedbackDetails();
      const wire = createV3WireFeedbackDetails(canonical);
      const parsed = v3FeedbackDetailsSchema.parse(wire);

      expect(parsed.received).toBe(true);
    });

    it('transforms null received to false', () => {
      const wire = { received: null };
      const parsed = v3FeedbackDetailsSchema.parse(wire);

      // V3 transforms null -> false
      expect(parsed.received).toBe(false);
    });

    it('verifies V3 details complete round-trip equality', () => {
      const canonical = createCanonicalFeedbackDetails();
      const wire = createV3WireFeedbackDetails(canonical);
      const parsed = v3FeedbackDetailsSchema.parse(wire);

      const result = compareCanonicalFeedbackDetails(canonical, parsed);

      expect(result.equal, `Differences: ${result.differences.join(', ')}`).toBe(true);
    });
  });
});

// -----------------------------------------------------------------------------
// Cross-Format Consistency
// -----------------------------------------------------------------------------

describe('Cross-Format Consistency', () => {
  describe('V2 and V3 message handling', () => {
    it('both formats preserve message content identically', () => {
      const canonical = createCanonicalFeedback();

      const v2Wire = createV2WireFeedback(canonical);
      const v3Wire = createV3WireFeedback(canonical);

      const v2Parsed = v2FeedbackSchema.parse(v2Wire);
      const v3Parsed = v3FeedbackRecord.parse(v3Wire);

      // Message content should be identical
      expect(v2Parsed.msg).toBe(v3Parsed.msg);
      expect(v2Parsed.msg).toBe(canonical.msg);
    });
  });

  describe('stamp type differences', () => {
    it('documents V2 string vs V3 Date semantic difference', () => {
      const canonical = createCanonicalFeedback();

      const v2Wire = createV2WireFeedback(canonical);
      const v3Wire = createV3WireFeedback(canonical);

      const v2Parsed = v2FeedbackSchema.parse(v2Wire);
      const v3Parsed = v3FeedbackRecord.parse(v3Wire);

      // V2: stamp is string
      // V3: stamp is Date (matches contract)
      expect(typeof v2Parsed.stamp).toBe('string');
      expect(v3Parsed.stamp).toBeInstanceOf(Date);

      // Both represent the same timestamp
      const v2Timestamp = new Date(v2Parsed.stamp).getTime();
      const v3Timestamp = v3Parsed.stamp.getTime();
      expect(v2Timestamp).toBe(v3Timestamp);
    });
  });

  describe('details received handling', () => {
    it('V2 and V3 both output boolean for received', () => {
      const canonical = createCanonicalFeedbackDetails();

      const v2Wire = createV2WireFeedbackDetails(canonical);
      const v3Wire = createV3WireFeedbackDetails(canonical);

      const v2Parsed = v2FeedbackDetailsSchema.parse(v2Wire);
      const v3Parsed = v3FeedbackDetailsSchema.parse(v3Wire);

      // Both output boolean
      expect(typeof v2Parsed.received).toBe('boolean');
      expect(typeof v3Parsed.received).toBe('boolean');
      expect(v2Parsed.received).toBe(v3Parsed.received);
    });
  });
});
