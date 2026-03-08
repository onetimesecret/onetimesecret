// src/schemas/api/v1/requests/show-receipt-recent.ts
//
// Request schema for V1::Controllers::Index#show_receipt_recent
// GET /receipt/recent
//
// TODO: Review and adjust — this scaffold was auto-generated from
// the Ruby source parameter survey. Verify against the actual
// handler implementation before using in the OpenAPI pipeline.
//
// No request params. Returns recent receipts for authenticated user.

import { z } from 'zod';

// This endpoint accepts no request parameters.
// Path params (if any) are handled by the OpenAPI generator.
export const showReceiptRecentRequestSchema = z.object({});

export type ShowReceiptRecentRequest = z.infer<typeof showReceiptRecentRequestSchema>;
