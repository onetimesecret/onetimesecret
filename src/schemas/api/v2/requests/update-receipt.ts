// src/schemas/api/v2/requests/update-receipt.ts
//
// Request schema for V2::Logic::Secrets::UpdateReceipt
// PATCH /receipt/:identifier
//
//
// PATCH — body params TBD. Identifier is in path.

import { z } from 'zod';

// TODO: Add request parameters for this endpoint.
// Path params: identifier
export const updateReceiptRequestSchema = z.object({
  // TODO: fill in from V2::Logic::Secrets::UpdateReceipt raise_concerns / process
});

export type UpdateReceiptRequest = z.infer<typeof updateReceiptRequestSchema>;
