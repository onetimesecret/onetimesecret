// src/schemas/api/v3/responses/feedback.ts
//
// V3 API response schemas for feedback endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema } from '@/schemas/api/base';
import { feedbackSchema, feedbackDetailsSchema } from '@/schemas/shapes/v3/feedback';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const feedbackResponseSchema = createApiResponseSchema(feedbackSchema, feedbackDetailsSchema);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type FeedbackResponse = z.infer<typeof feedbackResponseSchema>;
