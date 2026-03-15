// src/schemas/api/v1/requests/show-secret.ts
//
// Request schema for V1::Controllers::Index#show_secret
// POST /secret/:key
//

import { z } from 'zod';

export const showSecretRequestSchema = z.object({
  /**
   * Do we include the secret here `key`?
   * No. The key is a path parameter (/secret/:key), not a body/query parameter. The generator already handles path
     params mechanically in buildPathParameters
   * */
  /** Passphrase if the secret is protected */
  passphrase: z.string().optional(),
  /** Set to "true" to proceed with reveal */
  continue: z.string().optional(),
});

export type ShowSecretRequest = z.infer<typeof showSecretRequestSchema>;
