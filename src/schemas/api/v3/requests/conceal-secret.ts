// src/schemas/api/v3/requests/conceal-secret.ts
//
// Request schema for V3::Logic::Secrets::ConcealSecret
// POST /secret/conceal
//
// V3 inherits V2's nesting — params nested under a "secret" key:
//   @payload = params['secret'] || {}
// See: apps/api/v2/logic/secrets/base_secret_action.rb#process_params
// V3::Logic::Secrets::ConcealSecret < V2::Logic::Secrets::ConcealSecret

import { z } from 'zod';

import { concealPayloadSchema } from '@/schemas/api/v2/requests/content/conceal';

export const concealSecretRequestSchema = z.object({
  /** Transport wrapper — inherited from V2 BaseSecretAction */
  secret: concealPayloadSchema,
});

export type ConcealSecretRequest = z.infer<typeof concealSecretRequestSchema>;
