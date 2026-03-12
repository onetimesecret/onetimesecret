// src/schemas/api/v2/requests/show-receipt.ts
//
// Request schema for V2::Logic::Secrets::ShowReceipt
// GET /receipt/:identifier
//
//
// GET — no body. Identifier is in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: identifier
export const showReceiptRequestSchema = z.object({
  // TODO: fill in from V2::Logic::Secrets::ShowReceipt raise_concerns / process
});

export type ShowReceiptRequest = z.infer<typeof showReceiptRequestSchema>;
