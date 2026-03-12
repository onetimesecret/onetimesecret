// src/schemas/api/v3/requests/show-multiple-receipts.ts
//
// Request schema for V3::Logic::Secrets::ShowMultipleReceipts
// POST /guest/receipts
//
//
// POST with array of identifiers to batch-fetch receipts.

import { z } from 'zod';

export const showMultipleReceiptsRequestSchema = z.object({
  /** Array of receipt identifiers */
  identifiers: z.array(z.string()),
});

export type ShowMultipleReceiptsRequest = z.infer<typeof showMultipleReceiptsRequestSchema>;
