// src/schemas/api/v3/requests/list-secret-status.ts
//
// Request schema for V3::Logic::Secrets::ListSecretStatus
// POST /secret/status
//
//
// POST with CSV or an array of identifiers to batch-check status.

import { z } from 'zod';

export const listSecretStatusRequestSchema = z.object({
  /** Secret identifiers as an array or comma-separated string. */
  identifiers: z.union([z.array(z.string()), z.string()]),
});

export type ListSecretStatusRequest = z.infer<typeof listSecretStatusRequestSchema>;
