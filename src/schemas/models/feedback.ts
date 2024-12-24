import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

export const feedbackSchema = createModelSchema({
  // Feedback content using consistent transform pattern
  msg: z.string().min(1).max(1500),
});

// Details schema for feedback-specific metadata
export const feedbackDetailsSchema = z.object({
  received: transforms.fromString.boolean.optional(),
});

// Export types
export type Feedback = z.infer<typeof feedbackSchema>;
export type FeedbackDetails = z.infer<typeof feedbackDetailsSchema>;
