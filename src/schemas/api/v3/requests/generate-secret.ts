// src/schemas/api/v3/requests/generate-secret.ts
//
// Request schema for V3::Logic::Secrets::GenerateSecret
// POST /secret/generate
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// Server generates the secret value. Existing Zod schemas in payloads/.

import { z } from 'zod';

export const generateSecretRequestSchema = z.object({
  /** Time-to-live in seconds */
  ttl: z.number().int().optional(),
  /** Passphrase to protect the secret */
  passphrase: z.string().optional(),
  /** Recipient email address(es) */
  recipient: z.array(z.email()).optional(),
  /** Custom domain for the share link */
  share_domain: z.string().optional(),
});

export type GenerateSecretRequest = z.infer<typeof generateSecretRequestSchema>;
