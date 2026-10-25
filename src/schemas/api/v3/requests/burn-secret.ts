// src/schemas/api/v3/requests/burn-secret.ts
//
// Request schema for V3::Logic::Secrets::BurnSecret
// POST /receipt/:identifier/burn
//
//
// Identifier is in path param, not body.

import { z } from 'zod';

export const burnSecretRequestSchema = z.object({
  /** Only boolean true or the string "true" confirms the burn. */
  continue: z.union([z.boolean(), z.string()]).optional(),
  /** Passphrase if the secret is protected. */
  passphrase: z.string().optional(),
});

export type BurnSecretRequest = z.infer<typeof burnSecretRequestSchema>;
