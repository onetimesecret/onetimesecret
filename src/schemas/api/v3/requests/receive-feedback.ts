// src/schemas/api/v3/requests/receive-feedback.ts
//
// Request schema for V3::Logic::ReceiveFeedback
// POST /feedback
//

import { z } from 'zod';

export const receiveFeedbackRequestSchema = z.object({
  /** Feedback message content */
  message: z.string(),
  /** Contact email (optional) */
  email: z.string().optional(),
});

export type ReceiveFeedbackRequest = z.infer<typeof receiveFeedbackRequestSchema>;
