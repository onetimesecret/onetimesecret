// src/schemas/contracts/feedback.ts
// @see src/tests/schemas/shapes/feedback.compat.spec.ts - Test fixtures
//
// Canonical feedback record schema - field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Feedback record contracts defining field names and output types.
 *
 * Feedback captures user-submitted messages (bug reports, feature requests,
 * general comments). These canonical schemas define the "what" (field names
 * and final types) without the "how" (wire-format transforms).
 *
 * Version-specific shapes in `shapes/v2/feedback.ts` and `shapes/v3/feedback.ts`
 * extend these with appropriate transforms for each API version.
 *
 * @module contracts/feedback
 * @category Contracts
 * @see {@link "shapes/v2/feedback"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/feedback"} - V3 wire format with native types
 */

import { z } from 'zod';

/**
 * Canonical feedback record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * Feedback messages are stored in a sorted set with the message
 * as the member and the timestamp as the score. The Ruby model
 * auto-trims entries older than 30 days.
 *
 * @category Contracts
 * @see {@link "shapes/v2/feedback".feedbackSchema} - V2 wire format
 * @see {@link "shapes/v3/feedback".feedbackSchema} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const feedbackV3 = feedbackCanonical.extend({
 *   stamp: transforms.fromNumber.toDate,
 * });
 *
 * // Derive TypeScript type
 * type Feedback = z.infer<typeof feedbackCanonical>;
 * ```
 */
export const feedbackCanonical = z.object({
  /** The feedback message content (1-1500 characters). */
  msg: z.string().min(1).max(1500),

  /** Timestamp when the feedback was submitted. */
  stamp: z.date(),
});

/**
 * Canonical feedback details contract.
 *
 * Metadata returned alongside feedback records for display logic.
 * Controls acknowledgment status of feedback.
 *
 * @category Contracts
 * @see {@link "shapes/v2/feedback".feedbackDetailsSchema} - V2 wire format
 *
 * @example
 * ```typescript
 * const details = feedbackDetailsCanonical.parse(apiResponse.details);
 * if (details.received) {
 *   // Feedback has been acknowledged
 * }
 * ```
 */
export const feedbackDetailsCanonical = z.object({
  /** Whether the feedback has been received/acknowledged. */
  received: z.boolean(),
});

// -----------------------------------------------------------------------------
// Type exports
// -----------------------------------------------------------------------------

/** TypeScript type for feedback record. */
export type FeedbackCanonical = z.infer<typeof feedbackCanonical>;

/** TypeScript type for feedback details metadata. */
export type FeedbackDetailsCanonical = z.infer<typeof feedbackDetailsCanonical>;
