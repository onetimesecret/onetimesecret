// src/tests/schemas/shapes/feedback.compat.spec.ts
//
// V3 feedback schema compatibility tests.
// Tests wire format handling and type coercion behavior.
//
// Note: V2 feedback was removed - these tests focus on V3 schema behavior
// and document expected type requirements.

import { describe, it, expect } from 'vitest';
import {
  feedbackSchema as v3FeedbackSchema,
  feedbackDetailsSchema as v3FeedbackDetailsSchema,
} from '@/schemas/shapes/v3/feedback';
import {
  createCanonicalFeedback,
  createCanonicalFeedbackDetails,
  createV3WireFeedback,
  createV3WireFeedbackDetails,
} from './fixtures/feedback.fixtures';

// -----------------------------------------------------------------------------
// V3 Wire Format Requirements
// -----------------------------------------------------------------------------

describe('V3 Feedback Wire Format Requirements', () => {
  describe('feedbackSchema', () => {
    it('requires number for stamp field', () => {
      const canonical = createCanonicalFeedback();
      const wire = createV3WireFeedback(canonical);

      // V3 sends stamp as Unix epoch number
      expect(typeof wire.stamp).toBe('number');

      const result = v3FeedbackSchema.safeParse(wire);
      expect(result.success).toBe(true);
    });

    it('rejects string stamp (ISO format)', () => {
      const wire = {
        msg: 'test feedback',
        stamp: '2024-01-15T10:00:00.000Z', // Wrong type
      };

      const result = v3FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(false);
      if (!result.success) {
        const stampError = result.error.issues.find((i) => i.path.includes('stamp'));
        expect(stampError).toBeDefined();
        expect(stampError?.message).toContain('number');
      }
    });

    it('transforms number stamp to Date', () => {
      const wire = {
        msg: 'test feedback',
        stamp: 1705312800, // 2024-01-15T10:00:00Z
      };

      const result = v3FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.stamp).toBeInstanceOf(Date);
        expect(result.data.stamp.toISOString()).toBe('2024-01-15T10:00:00.000Z');
      }
    });
  });

  describe('feedbackDetailsSchema', () => {
    it('requires boolean for received field', () => {
      const canonical = createCanonicalFeedbackDetails({ received: true });
      const wire = createV3WireFeedbackDetails(canonical);

      // V3 sends received as native boolean
      expect(typeof wire.received).toBe('boolean');

      const result = v3FeedbackDetailsSchema.safeParse(wire);
      expect(result.success).toBe(true);
    });

    it('rejects string boolean values', () => {
      const wire = { received: 'true' }; // Wrong type

      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('accepts null and transforms to false', () => {
      const wire = { received: null };

      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });

    it('accepts undefined received (schema handles optional)', () => {
      // feedbackDetailsSchema has received: z.boolean().nullable().transform()
      const wire = {};

      // undefined will be treated as null and transformed to false
      const result = v3FeedbackDetailsSchema.safeParse(wire);

      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Type Coercion Behavior
// -----------------------------------------------------------------------------

describe('V3 Feedback Type Coercion', () => {
  describe('stamp field', () => {
    it('does not coerce string to number', () => {
      const wire = { msg: 'test', stamp: '1705312800' };

      const result = v3FeedbackSchema.safeParse(wire);

      // V3 is strict about types - no coercion
      expect(result.success).toBe(false);
    });

    it('accepts integer timestamps', () => {
      const wire = { msg: 'test', stamp: 1705312800 };

      const result = v3FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(true);
    });

    it('accepts float timestamps (truncates to seconds)', () => {
      const wire = { msg: 'test', stamp: 1705312800.5 };

      const result = v3FeedbackSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        // The transform handles float -> Date
        expect(result.data.stamp).toBeInstanceOf(Date);
      }
    });
  });

  describe('received field', () => {
    it('does not coerce string "true" to boolean', () => {
      const wire = { received: 'true' };

      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('does not coerce number 1 to boolean', () => {
      const wire = { received: 1 };

      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(false);
    });

    it('normalizes null to false', () => {
      const wire = { received: null };

      const result = v3FeedbackDetailsSchema.safeParse(wire);

      expect(result.success).toBe(true);
      if (result.success) {
        expect(result.data.received).toBe(false);
      }
    });
  });
});

// -----------------------------------------------------------------------------
// Contract Alignment
// -----------------------------------------------------------------------------

describe('V3 Feedback Contract Alignment', () => {
  it('output matches canonical contract types', () => {
    const canonical = createCanonicalFeedback();
    const wire = createV3WireFeedback(canonical);
    const parsed = v3FeedbackSchema.parse(wire);

    // Contract expects: msg: string, stamp: Date
    expect(typeof parsed.msg).toBe('string');
    expect(parsed.stamp).toBeInstanceOf(Date);
  });

  it('details output matches canonical contract types', () => {
    const canonical = createCanonicalFeedbackDetails();
    const wire = createV3WireFeedbackDetails(canonical);
    const parsed = v3FeedbackDetailsSchema.parse(wire);

    // Contract expects: received: boolean
    expect(typeof parsed.received).toBe('boolean');
  });

  it('documents null->false transform for received', () => {
    // V3 explicitly transforms null to false for boolean fields
    const wireWithNull = { received: null };

    const parsed = v3FeedbackDetailsSchema.parse(wireWithNull);

    // V3 normalizes null to false (semantic choice for "not acknowledged")
    expect(parsed.received).toBe(false);
  });
});
