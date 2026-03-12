// src/schemas/api/v2/requests/reveal-secret.ts
//
// Request schema for V2::Logic::Secrets::RevealSecret
// POST /secret/:identifier/reveal
//

import { z } from 'zod';

export const revealSecretRequestSchema = z.object({
  /** Passphrase if the secret is protected */
  passphrase: z.string().optional(),
  /** Set to "true" to proceed */
  continue: z.string().optional(),
});

export type RevealSecretRequest = z.infer<typeof revealSecretRequestSchema>;
