// src/schemas/api/v3/requests/show-multiple-receipts.ts
//
// Request schema for V3::Logic::Secrets::ShowMultipleReceipts
// POST /guest/receipts
//
//
// POST with CSV or an array of identifiers to batch-fetch receipts.

import { z } from 'zod';

export const showMultipleReceiptsRequestSchema = z.object({
  /** Receipt identifiers as an array or comma-separated string (up to 25 after sanitization). */
  identifiers: z.union([z.array(z.string()), z.string()]),
});

export type ShowMultipleReceiptsRequest = z.infer<typeof showMultipleReceiptsRequestSchema>;
