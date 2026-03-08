// src/schemas/api/v3/requests/list-receipts.ts
//
// Request schema for V3::Logic::Secrets::ListReceipts
// GET /receipt/recent
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// GET — no body. Returns recent receipts.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const listReceiptsRequestSchema = z.object({});

export type ListReceiptsRequest = z.infer<typeof listReceiptsRequestSchema>;
