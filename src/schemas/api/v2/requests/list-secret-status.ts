// src/schemas/api/v2/requests/list-secret-status.ts
//
// Request schema for V2::Logic::Secrets::ListSecretStatus
// POST /secret/status
//
//
// POST with array of identifiers to batch-check status.

import { z } from 'zod';

export const listSecretStatusRequestSchema = z.object({
  /** Array of secret identifiers to check */
  identifiers: z.array(z.string()),
});

export type ListSecretStatusRequest = z.infer<typeof listSecretStatusRequestSchema>;
