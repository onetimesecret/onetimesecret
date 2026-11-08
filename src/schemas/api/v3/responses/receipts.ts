// src/schemas/api/v3/responses/receipts.ts
//
// V3 API response schemas for receipt endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiListResponseSchema, createApiResponseSchema } from '@/schemas/api/base';
import {
  receiptDetailsSchema,
  receiptListDetailsSchema,
  receiptListSchema,
  receiptSchema,
} from '@/schemas/shapes/v3/receipt';
import { z } from 'zod';
import { receiptSafeDumpRecordSchema } from './producer-records';

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const receiptResponseSchema = createApiResponseSchema(receiptSchema, receiptDetailsSchema);

/** PATCH emits only safe_dump, without GET's computed links or expiration. */
export const updateReceiptResponseSchema = z.strictObject({
  record: receiptSafeDumpRecordSchema,
});
export const receiptListResponseSchema = createApiListResponseSchema(
  receiptListSchema,
  receiptListDetailsSchema
);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptResponse = z.infer<typeof receiptResponseSchema>;
export type UpdateReceiptResponse = z.infer<typeof updateReceiptResponseSchema>;
export type ReceiptListResponse = z.infer<typeof receiptListResponseSchema>;
