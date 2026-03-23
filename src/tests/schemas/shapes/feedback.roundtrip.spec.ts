// src/tests/schemas/shapes/feedback.roundtrip.spec.ts
//
// Round-trip tests for V3 feedback schemas.
// Verifies: canonical -> wire format -> schema parse -> canonical (equality)
//
// V3 properly transforms stamp (number -> Date) and matches the contract.

import { describe, it, expect } from 'vitest';
import {
  feedbackSchema as v3FeedbackSchema,
  feedbackDetailsSchema as v3FeedbackDetailsSchema,
} from '@/schemas/shapes/v3/feedback';
import {
  createCanonicalFeedback,
  createCanonicalFeedbackDetails,
  createMaxLengthFeedback,
  createMinLengthFeedback,
  createReceivedFeedbackDetails,
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
// V3 Round-Trip Tests
// -----------------------------------------------------------------------------

describe('V3 Feedback Round-Trip', () => {
  describe('feedbackSchema', () => {
    it('round-trips feedback with Date stamp', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      // V3 transforms number -> Date
      expect(parsed.msg).toBe(canonical.msg);
      expectDatesEqual(parsed.stamp, canonical.stamp, 'stamp');
    });

    it('matches canonical type (stamp is Date)', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      // V3 output matches contract expectation
      expect(parsed.stamp).toBeInstanceOf(Date);
      expect(parsed.stamp.getTime()).toBe(canonical.stamp.getTime());
    });

    it('preserves message content through round-trip', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
    });

    it('handles maximum length message', () => {
      const canonical = createMaxLengthFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
      expect(parsed.msg.length).toBe(1500);
    });

    it('handles minimum length message', () => {
      const canonical = createMinLengthFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(canonical.msg);
      expect(parsed.msg.length).toBe(1);
    });

    it('verifies V3 complete round-trip equality', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      const result = compareCanonicalFeedback(canonical, parsed);

      expect(result.equal, `Differences: ${result.differences.join(', ')}`).toBe(true);
    });
  });

  describe('feedbackDetailsSchema', () => {
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
// Edge Cases
// -----------------------------------------------------------------------------

describe('V3 Feedback Edge Cases', () => {
  describe('message content preservation', () => {
    it('preserves special characters', () => {
      const specialMsg = 'Test with "quotes", <tags>, & ampersands!';
      const canonical = createCanonicalFeedback({ msg: specialMsg });

      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(specialMsg);
    });

    it('preserves unicode characters', () => {
      const unicodeMsg = 'Feedback with emoji and unicode chars';
      const canonical = createCanonicalFeedback({ msg: unicodeMsg });

      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(unicodeMsg);
    });

    it('preserves newlines', () => {
      const multilineMsg = 'Line 1\nLine 2\nLine 3';
      const canonical = createCanonicalFeedback({ msg: multilineMsg });

      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      expect(parsed.msg).toBe(multilineMsg);
    });
  });

  describe('timestamp precision', () => {
    it('epoch seconds loses millisecond precision', () => {
      const timestamp = new Date('2024-01-15T10:00:00.500Z');
      const canonical = createCanonicalFeedback({ stamp: timestamp });

      const wire = createV3WireFeedback(canonical);
      const parsed = v3FeedbackSchema.parse(wire);

      // V3 epoch seconds truncates to whole seconds
      const truncatedMs = Math.floor(timestamp.getTime() / 1000) * 1000;
      expect(parsed.stamp.getTime()).toBe(truncatedMs);

      // Original had 500ms
      expect(canonical.stamp.getMilliseconds()).toBe(500);

      // Parsed loses the 500ms
      expect(parsed.stamp.getMilliseconds()).toBe(0);
    });
  });
});

// -----------------------------------------------------------------------------
// Validation Tests
// -----------------------------------------------------------------------------

describe('V3 Feedback Validation', () => {
  describe('feedbackSchema', () => {
    it('rejects string for number stamp', () => {
      const wire = { msg: 'test', stamp: '2024-01-15T10:00:00Z' };
      const result = v3FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('accepts valid wire format', () => {
      const wire = { msg: 'test', stamp: 1705312800 };
      const result = v3FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(true);
    });
  });

  describe('feedbackDetailsSchema', () => {
    it('rejects string "true" for boolean field', () => {
      const wire = { received: 'true' };
      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('accepts null for received (transforms to false)', () => {
      const wire = { received: null };
      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });

    it('accepts native boolean values', () => {
      expect(v3FeedbackDetailsSchema.parse({ received: true }).received).toBe(true);
      expect(v3FeedbackDetailsSchema.parse({ received: false }).received).toBe(false);
    });
  });
});
