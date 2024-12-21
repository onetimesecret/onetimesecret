import { createModelSchema } from '@/schemas/models/base';
import { createResponseSchema } from '@/schemas/models/response';
import { transforms } from '@/utils/transforms';
import { z } from 'zod';

/**
 * @fileoverview Feedback schema with standardized transformations
 *
 * Key improvements:
 * 1. Consistent use of transforms for type conversion
 * 2. Standardized response schema pattern
 * 3. Clear type boundaries
 */

// Base feedback fields
export const feedbackSchema = createModelSchema({
  // Feedback content
  msg: z.string().min(1),
});

// Details schema for feedback-specific metadata
export const feedbackDetailsSchema = z.object({
  received: transforms.fromString.boolean.optional(),
});

// Export types
export type Feedback = z.infer<typeof feedbackSchema>;
export type FeedbackDetails = z.infer<typeof feedbackDetailsSchema>;

// API response schema
export const feedbackResponseSchema = createResponseSchema(feedbackSchema, feedbackDetailsSchema);
export type FeedbackResponse = z.infer<typeof feedbackResponseSchema>;
