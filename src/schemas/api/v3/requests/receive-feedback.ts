// src/schemas/api/v3/requests/receive-feedback.ts
//
// Request schema for V3::Logic::ReceiveFeedback
// POST /feedback
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const receiveFeedbackRequestSchema = z.object({
  /** Feedback message content */
  message: z.string(),
  /** Contact email (optional) */
  email: z.string().optional(),
});

export type ReceiveFeedbackRequest = z.infer<typeof receiveFeedbackRequestSchema>;
