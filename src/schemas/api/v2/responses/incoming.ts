// src/schemas/api/v2/responses/incoming.ts
//
// Response schemas for incoming secret endpoints.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  incomingConfigSchema,
  incomingSecretResponseSchema,
  validateRecipientResponseSchema,
} from '@/schemas/api/incoming';
import { z } from 'zod';

export const incomingConfigResponseSchema = createApiResponseSchema(incomingConfigSchema);

// Re-export — these are already full response schemas defined in the incoming module
export { incomingSecretResponseSchema, validateRecipientResponseSchema };

// Wrap validateRecipient in the standard envelope
export const validateRecipientEnvelopeSchema = createApiResponseSchema(validateRecipientResponseSchema);

export type IncomingConfigResponse = z.infer<typeof incomingConfigResponseSchema>;
export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;
export type ValidateRecipientResponse = z.infer<typeof validateRecipientEnvelopeSchema>;
