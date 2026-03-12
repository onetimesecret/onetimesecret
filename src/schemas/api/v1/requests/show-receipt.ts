// src/schemas/api/v1/requests/show-receipt.ts
//
// Request schema for V1::Controllers::Index#show_receipt
// GET /receipt/:key
//
//
// GET requires no body params. POST accepts same as GET (key is in path).

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: key
export const showReceiptRequestSchema = z.object({
  // TODO: fill in from V1::Controllers::Index#show_receipt raise_concerns / process
});

export type ShowReceiptRequest = z.infer<typeof showReceiptRequestSchema>;
