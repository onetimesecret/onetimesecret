// src/schemas/api/v3/requests/conceal-secret.ts
//
// Request schema for V3::Logic::Secrets::ConcealSecret
// POST /secret/conceal
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// V2: params nested under secret={...}. V3: same structure. Existing Zod schemas in payloads/.

import { z } from 'zod';

export const concealSecretRequestSchema = z.object({
  /** The secret content to conceal */
  secret: z.string(),
  /** Time-to-live in seconds */
  ttl: z.number().int().optional(),
  /** Passphrase to protect the secret */
  passphrase: z.string().optional(),
  /** Recipient email address(es) */
  recipient: z.array(z.email()).optional(),
  /** Custom domain for the share link */
  share_domain: z.string().optional(),
});

export type ConcealSecretRequest = z.infer<typeof concealSecretRequestSchema>;
