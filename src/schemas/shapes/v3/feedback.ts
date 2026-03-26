// src/schemas/shapes/v3/feedback.ts
//
// V3 wire-format shapes for feedback.
// Derives from contracts, adding V3-specific timestamp transforms (number -> Date).

import { feedbackCanonical, feedbackDetailsCanonical } from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// -----------------------------------------------------------------------------
// V3 feedback shapes
// -----------------------------------------------------------------------------

/**
 * V3 feedback record.
 *
 * Derives from contract, adds V3 timestamp transform (number -> Date).
 * V3 API sends timestamps as Unix epoch seconds.
 */
export const feedbackSchema = feedbackCanonical.extend({
  stamp: transforms.fromNumber.toDate,
});

/**
 * V3 feedback details.
 *
 * Adds null -> false transform for the received boolean field.
 * Handles cases where the API returns null for unset acknowledgment status.
 */
export const feedbackDetailsSchema = feedbackDetailsCanonical.extend({
  received: z
    .boolean()
    .nullable()
    .transform((v) => v ?? false),
});

// -----------------------------------------------------------------------------
// Type exports
// -----------------------------------------------------------------------------

export type Feedback = z.infer<typeof feedbackSchema>;
export type FeedbackDetails = z.infer<typeof feedbackDetailsSchema>;
