// src/schemas/api/v3/responses/receipts.ts
//
// V3 API response schemas for receipt endpoints.
// Wraps shapes from shapes/v3/ in API envelopes.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  receiptSchema,
  receiptDetailsSchema,
  receiptListSchema,
  receiptListDetailsSchema,
} from '@/schemas/shapes/v3/receipt';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Envelope-wrapped response schemas
// ─────────────────────────────────────────────────────────────────────────────

export const receiptResponseSchema = createApiResponseSchema(receiptSchema, receiptDetailsSchema);
export const receiptListResponseSchema = createApiListResponseSchema(receiptListSchema, receiptListDetailsSchema);

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptResponse = z.infer<typeof receiptResponseSchema>;
export type ReceiptListResponse = z.infer<typeof receiptListResponseSchema>;
