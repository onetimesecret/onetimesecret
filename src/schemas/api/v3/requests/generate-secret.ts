// src/schemas/api/v3/requests/generate-secret.ts
//
// Request schema for V3::Logic::Secrets::GenerateSecret
// POST /secret/generate
//
// V3 inherits V2's nesting — params nested under a "secret" key:
//   @payload = params['secret'] || {}
// See: apps/api/v2/logic/secrets/base_secret_action.rb#process_params
// V3::Logic::Secrets::GenerateSecret < V2::Logic::Secrets::GenerateSecret

import { z } from 'zod';

import { generatePayloadSchema } from './content/generate';

export const generateSecretRequestSchema = z.object({
  /** Transport wrapper — inherited from V2 BaseSecretAction */
  secret: generatePayloadSchema,
});

export type GenerateSecretRequest = z.infer<typeof generateSecretRequestSchema>;
