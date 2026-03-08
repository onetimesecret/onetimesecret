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

export const generateSecretRequestSchema = z.object({
  /** Nested payload — inherited from V2 BaseSecretAction */
  secret: z.object({
    /** Time-to-live in seconds */
    ttl: z.number().int().optional(),
    /** Passphrase to protect the secret */
    passphrase: z.string().optional(),
    /** Recipient email address(es) */
    recipient: z.array(z.email()).optional(),
    /** Custom domain for the share link */
    share_domain: z.string().optional(),
  }),
});

export type GenerateSecretRequest = z.infer<typeof generateSecretRequestSchema>;
