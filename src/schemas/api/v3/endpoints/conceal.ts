// src/schemas/api/v3/endpoints/conceal.ts

import { receiptBaseSchema, secretSchema } from '@/schemas/models';
import { z } from 'zod';

/**
 * Schema for receipt returned by conceal endpoint
 * Uses base schema since URLs are not computed during creation
 */
export const concealReceiptSchema = receiptBaseSchema.extend({
  identifier: z.string(),
});

/**
 * Schema for combined secret and receipt (conceal data)
 * Uses conceal-specific receipt schema without URL fields
 */
export const concealDataSchema = z.object({
  metadata: concealReceiptSchema, // API response key remains 'metadata' for compatibility
  secret: secretSchema,
  share_domain: z.string().nullable(),
});

export type ConcealData = z.infer<typeof concealDataSchema>;
export type ConcealReceipt = z.infer<typeof concealReceiptSchema>;
