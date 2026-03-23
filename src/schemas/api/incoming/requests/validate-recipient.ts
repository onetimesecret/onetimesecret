// src/schemas/api/incoming/requests/validate-recipient.ts

import { z } from 'zod';

/**
 * Schema for recipient validation request
 */
export const validateRecipientPayloadSchema = z.object({
  recipient: z.string().min(1),
});

export type ValidateRecipientPayload = z.infer<typeof validateRecipientPayloadSchema>;
