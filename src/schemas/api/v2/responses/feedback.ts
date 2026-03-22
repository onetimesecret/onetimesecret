// src/schemas/api/v2/responses/feedback.ts
//
// Response schema for the feedback endpoint.

import { createApiResponseSchema } from '@/schemas/api/base';
import { feedbackDetailsSchema, feedbackSchema } from '@/schemas/shapes/v2/feedback';
import { z } from 'zod';

export const feedbackResponseSchema = createApiResponseSchema(feedbackSchema, feedbackDetailsSchema);

export type FeedbackResponse = z.infer<typeof feedbackResponseSchema>;
