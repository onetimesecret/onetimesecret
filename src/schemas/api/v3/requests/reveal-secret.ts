// src/schemas/api/v3/requests/reveal-secret.ts
//
// Request schema for V3::Logic::Secrets::RevealSecret
// POST /secret/:identifier/reveal
//

import { z } from 'zod';

export const revealSecretRequestSchema = z.object({
  /** Passphrase if the secret is protected */
  passphrase: z.string().optional(),
  /** Only boolean true or the string "true" proceeds with reveal. */
  continue: z.union([z.boolean(), z.string()]).optional(),
});

export type RevealSecretRequest = z.infer<typeof revealSecretRequestSchema>;
