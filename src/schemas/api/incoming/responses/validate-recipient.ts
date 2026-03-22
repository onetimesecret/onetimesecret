// src/schemas/api/incoming/responses/validate-recipient.ts

import { z } from 'zod';

/**
 * Schema for recipient validation response
 */
export const validateRecipientResponseSchema = z.object({
  recipient: z.string(),
  valid: z.boolean(),
});

export type ValidateRecipientResponse = z.infer<typeof validateRecipientResponseSchema>;
