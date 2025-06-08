import { transforms } from '@/schemas/transforms';
import { z } from 'zod/v4';

export const feedbackSchema = z.object({
  // Feedback content using consistent transform pattern
  msg: z.string().min(1).max(1500),
  stamp: z.string(),
});

// Details schema for feedback-specific metadata
export const feedbackDetailsSchema = z.object({
  received: transforms.fromString.boolean.optional(),
});

// Export types
export type Feedback = z.infer<typeof feedbackSchema>;
export type FeedbackDetails = z.infer<typeof feedbackDetailsSchema>;
