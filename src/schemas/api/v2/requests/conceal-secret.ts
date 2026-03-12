// src/schemas/api/v2/requests/conceal-secret.ts
//
// Request schema for V2::Logic::Secrets::ConcealSecret
// POST /secret/conceal
//
// V2 nests all create/conceal params under a "secret" key:
//   @payload = params['secret'] || {}
// See: apps/api/v2/logic/secrets/base_secret_action.rb#process_params

import { z } from 'zod';

import { concealPayloadSchema } from './content/conceal';

export const concealSecretRequestSchema = z.object({
  /** Transport wrapper — V2 BaseSecretAction unwraps params['secret'] */
  secret: concealPayloadSchema,
});

export type ConcealSecretRequest = z.infer<typeof concealSecretRequestSchema>;
