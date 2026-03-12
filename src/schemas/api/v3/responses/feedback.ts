// src/schemas/api/v3/responses/feedback.ts
//
// V3 JSON wire-format schema for the feedback endpoint.

import { createApiResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

const feedbackRecord = z.object({
  msg: z.string(),
  stamp: z.string(),
});

const feedbackDetails = z.object({
  received: z.boolean().optional(),
});

export const feedbackResponseSchema = createApiResponseSchema(feedbackRecord, feedbackDetails);

export type FeedbackResponse = z.infer<typeof feedbackResponseSchema>;
