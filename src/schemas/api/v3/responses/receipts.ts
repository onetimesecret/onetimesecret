// src/schemas/api/v3/responses/receipts.ts
//
// V3 API response schemas for receipt endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  receiptRecord,
  receiptDetails,
  receiptListRecord,
  receiptListDetails,
} from '@/schemas/shapes/v3/receipt';
import { z } from 'zod';

// Re-export shapes for consumers that import from responses
export { receiptBaseRecord } from '@/schemas/shapes/v3/receipt';

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const receiptResponseSchema = createApiResponseSchema(receiptRecord, receiptDetails);
export const receiptListResponseSchema = createApiListResponseSchema(receiptListRecord, receiptListDetails);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptResponse = z.infer<typeof receiptResponseSchema>;
export type ReceiptListResponse = z.infer<typeof receiptListResponseSchema>;
