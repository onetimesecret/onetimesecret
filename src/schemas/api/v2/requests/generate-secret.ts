// src/schemas/api/v2/requests/generate-secret.ts
//
// Request schema for V2::Logic::Secrets::GenerateSecret
// POST /secret/generate
//
// V2 nests all create/generate params under a "secret" key:
//   @payload = params['secret'] || {}
// See: apps/api/v2/logic/secrets/base_secret_action.rb#process_params

import { z } from 'zod';

import { generatePayloadSchema } from '@/schemas/api/v3/payloads/generate';

export const generateSecretRequestSchema = z.object({
  /** Transport wrapper — V2 BaseSecretAction unwraps params['secret'] */
  secret: generatePayloadSchema,
});

export type GenerateSecretRequest = z.infer<typeof generateSecretRequestSchema>;
