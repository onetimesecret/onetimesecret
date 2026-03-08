// src/schemas/api/v3/requests/validate-recipient.ts
//
// Request schema for V3::Logic::Incoming::ValidateRecipient
// POST /incoming/validate
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const validateRecipientRequestSchema = z.object({
  /** Recipient hash to validate */
  recipient: z.string(),
});

export type ValidateRecipientRequest = z.infer<typeof validateRecipientRequestSchema>;
