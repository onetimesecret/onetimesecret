// src/schemas/api/v2/responses/receipts.ts
//
// Response schemas for receipt endpoints.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  receiptRecordsDetailsSchema,
  receiptRecordsSchema,
} from './recent';
import { receiptDetailsSchema, receiptSchema } from '@/schemas/shapes/v2/receipt';
import { z } from 'zod';

export const receiptResponseSchema = createApiResponseSchema(receiptSchema, receiptDetailsSchema);
export const receiptListResponseSchema = createApiListResponseSchema(receiptRecordsSchema, receiptRecordsDetailsSchema);

export type ReceiptResponse = z.infer<typeof receiptResponseSchema>;
export type ReceiptListResponse = z.infer<typeof receiptListResponseSchema>;
