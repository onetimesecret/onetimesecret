// src/schemas/api/v3/requests/receive-feedback.ts
//
// Request schema for V3::Logic::ReceiveFeedback
// POST /feedback
//

import { z } from 'zod';

export const receiveFeedbackRequestSchema = z.object({
  /** Feedback text; the server sanitizes, truncates, and rejects empty content. */
  msg: z.string().min(1),
  /** Optional timezone metadata, sanitized and truncated by the server. */
  tz: z.string().optional(),
});

export type ReceiveFeedbackRequest = z.infer<typeof receiveFeedbackRequestSchema>;
