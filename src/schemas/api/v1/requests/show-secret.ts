// src/schemas/api/v1/requests/show-secret.ts
//
// Request schema for V1::Controllers::Index#show_secret
// POST /secret/:key
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.

import { z } from 'zod';

export const showSecretRequestSchema = z.object({
  // what about the /secret/:key path param? OpenAPI generator should handle that, but we may want to include it here for clarity.
  /** Passphrase if the secret is protected */
  passphrase: z.string().optional(),
  /** Set to "true" to proceed with reveal */
  continue: z.string().optional(),
});

export type ShowSecretRequest = z.infer<typeof showSecretRequestSchema>;
