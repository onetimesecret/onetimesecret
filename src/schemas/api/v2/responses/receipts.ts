// src/schemas/api/v2/responses/receipts.ts
//
// Response schemas for receipt endpoints.

import { createApiListResponseSchema, createApiResponseSchema } from '@/schemas/api/base';
import {
  receiptDetailsSchema,
  receiptListDetailsSchema,
  receiptListSchema,
  receiptSchema,
} from '@/schemas/shapes/v2/receipt';
import { z } from 'zod';

export const receiptResponseSchema = createApiResponseSchema(receiptSchema, receiptDetailsSchema);
export const receiptListResponseSchema = createApiListResponseSchema(
  receiptListSchema,
  receiptListDetailsSchema
);

export type ReceiptResponse = z.infer<typeof receiptResponseSchema>;
export type ReceiptListResponse = z.infer<typeof receiptListResponseSchema>;
