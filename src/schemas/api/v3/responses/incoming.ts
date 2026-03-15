// src/schemas/api/v3/responses/incoming.ts
//
// Incoming secret response schemas. These already use JSON-native types
// in the source module — re-exported here for V3 registry assembly.

import { createApiResponseSchema } from '@/schemas/api/base';
import {
  incomingConfigSchema,
  incomingSecretResponseSchema,
  validateRecipientResponseSchema,
} from '@/schemas/api/incoming';
import { z } from 'zod';

export const incomingConfigResponseSchema = createApiResponseSchema(incomingConfigSchema);
export { incomingSecretResponseSchema };
export const validateRecipientEnvelopeSchema = createApiResponseSchema(validateRecipientResponseSchema);

export type IncomingConfigResponse = z.infer<typeof incomingConfigResponseSchema>;
export type IncomingSecretResponse = z.infer<typeof incomingSecretResponseSchema>;
export type ValidateRecipientResponse = z.infer<typeof validateRecipientEnvelopeSchema>;
