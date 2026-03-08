// src/schemas/api/v3/requests/create-incoming-secret.ts
//
// Request schema for V3::Logic::Incoming::CreateIncomingSecret
// POST /incoming/secret
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// Incoming secret — TTL and passphrase set by config, not request.

import { z } from 'zod';

export const createIncomingSecretRequestSchema = z.object({
  /** The secret content */
  secret: z.string(),
  /** Memo for the recipient (max ~50 chars) */
  memo: z.string().optional(),
  /** Recipient hash lookup */
  recipient: z.record(z.string(), z.string()),
});

export type CreateIncomingSecretRequest = z.infer<typeof createIncomingSecretRequestSchema>;
