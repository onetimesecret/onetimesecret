// src/schemas/api/v3/requests/validate-recipient.ts
//
// Request schema for V3::Logic::Incoming::ValidateRecipient
// POST /incoming/validate
//

import { z } from 'zod';

export const validateRecipientRequestSchema = z.object({
  /** Recipient hash to validate */
  recipient: z.string(),
});

export type ValidateRecipientRequest = z.infer<typeof validateRecipientRequestSchema>;
