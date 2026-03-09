// src/schemas/api/v2/endpoints/secrets.ts
//
// Endpoint-level data shapes for the secrets domain.
// V2 owns these definitions — the business logic originates in V2 handlers.
// V3 previously re-exported these; now consumers import directly.

import { receiptBaseSchema, secretSchema } from '@/schemas/models';
import { z } from 'zod';

/**
 * Schema for receipt returned by conceal endpoint.
 * Uses base schema since URLs are not computed during creation.
 */
export const concealReceiptSchema = receiptBaseSchema.extend({
  identifier: z.string(),
});

/**
 * Schema for combined secret and receipt (conceal data).
 * Uses conceal-specific receipt schema without URL fields.
 *
 * Both V2 and V3 conceal/generate endpoints return this shape.
 * V3's ModernResponseFormat strips any legacy "metadata" key from
 * the Ruby response; the schema already uses "receipt" exclusively.
 */
export const concealDataSchema = z.object({
  receipt: concealReceiptSchema,
  secret: secretSchema,
  share_domain: z.string().nullable(),
});

export type ConcealData = z.infer<typeof concealDataSchema>;
export type ConcealReceipt = z.infer<typeof concealReceiptSchema>;
