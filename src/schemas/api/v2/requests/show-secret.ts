// src/schemas/api/v2/requests/show-secret.ts
//
// Request schema for V2::Logic::Secrets::ShowSecret
// GET /secret/:identifier
//
//
// GET — no body. Identifier is in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: identifier
export const showSecretRequestSchema = z.object({
  // TODO: fill in from V2::Logic::Secrets::ShowSecret raise_concerns / process
});

export type ShowSecretRequest = z.infer<typeof showSecretRequestSchema>;
