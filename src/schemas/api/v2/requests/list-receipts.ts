// src/schemas/api/v2/requests/list-receipts.ts
//
// Request schema for V2::Logic::Secrets::ListReceipts
// GET /receipt/recent
//
//
// GET — no body. Returns recent receipts.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const listReceiptsRequestSchema = z.object({});

export type ListReceiptsRequest = z.infer<typeof listReceiptsRequestSchema>;
