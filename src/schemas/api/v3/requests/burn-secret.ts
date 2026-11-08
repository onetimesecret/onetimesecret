// src/schemas/api/v3/requests/burn-secret.ts
//
// Request schema for V3::Logic::Secrets::BurnSecret
// POST /receipt/:identifier/burn
//
//
// Identifier is in path param, not body.

import { z } from 'zod';

export const burnSecretRequestSchema = z.object({
  /**
   * Required confirmation. The burn runs only for `true` (JSON) or `"true"`
   * (form-encoded); any other value, or leaving it out, is refused with a 422
   * on this field and the secret is left in place (#4878).
   */
  continue: z.union([z.literal(true), z.literal('true')]),
  /** Passphrase if the secret is protected. */
  passphrase: z.string().optional(),
});

export type BurnSecretRequest = z.infer<typeof burnSecretRequestSchema>;
