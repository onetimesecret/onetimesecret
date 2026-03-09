// src/schemas/api/v3/responses/receipts.ts
//
// V3 JSON wire-format schemas for receipt endpoints.
// Timestamps are Unix epoch (UTC seconds), booleans/numbers are native JSON types.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas
// ─────────────────────────────────────────────────────────────────────────────

const receiptStateValues = [
  'new', 'shared', 'received', 'revealed', 'burned',
  'viewed', 'previewed', 'expired', 'orphaned',
] as const;

/** Base receipt fields shared between list and detail views. */
const receiptBaseRecord = z.object({
  identifier: z.string(),
  created: z.number(),            // Unix epoch (UTC seconds)
  updated: z.number(),            // Unix epoch (UTC seconds)
  key: z.string(),
  shortid: z.string(),
  secret_shortid: z.string().optional(),
  recipients: z.array(z.string()).or(z.string()).nullable().optional(),
  share_domain: z.string().nullable().optional(),
  secret_ttl: z.number(),         // seconds
  receipt_ttl: z.number(),        // seconds
  lifespan: z.number(),           // seconds
  state: z.enum(receiptStateValues),
  has_passphrase: z.boolean().optional(),

  // Timestamp fields (Unix epoch or null)
  shared: z.number().nullable().optional(),
  received: z.number().nullable().optional(),     // @deprecated — use revealed
  viewed: z.number().nullable().optional(),       // @deprecated — use previewed
  previewed: z.number().nullable().optional(),
  revealed: z.number().nullable().optional(),
  burned: z.number().nullable().optional(),

  // Boolean status flags
  is_viewed: z.boolean(),         // @deprecated — use is_previewed
  is_received: z.boolean(),       // @deprecated — use is_revealed
  is_previewed: z.boolean().optional(),
  is_revealed: z.boolean().optional(),
  is_burned: z.boolean(),
  is_destroyed: z.boolean(),
  is_expired: z.boolean(),
  is_orphaned: z.boolean(),

  memo: z.string().nullable().optional(),
  kind: z.enum(['generate', 'conceal']).or(z.literal('')).nullable().optional(),
});

/** Full receipt for single-record view (adds URL paths and expiration). */
const receiptRecord = receiptBaseRecord.extend({
  secret_identifier: z.string().nullish(),
  secret_state: z.enum(receiptStateValues).nullish(),
  natural_expiration: z.string(),
  expiration: z.number(),         // Unix epoch (UTC seconds)
  expiration_in_seconds: z.number(),
  share_path: z.string(),
  burn_path: z.string(),
  receipt_path: z.string(),
  share_url: z.string(),
  receipt_url: z.string(),
  burn_url: z.string(),
});

/** Detail fields for single receipt view. */
const receiptDetails = z.object({
  type: z.literal('record'),
  display_lines: z.number(),
  no_cache: z.boolean(),
  secret_realttl: z.number().nullable().optional(),
  view_count: z.number().nullable(),
  has_passphrase: z.boolean(),
  can_decrypt: z.boolean(),
  secret_value: z.string().nullable().optional(),
  show_secret: z.boolean(),
  show_secret_link: z.boolean(),
  show_receipt_link: z.boolean(),
  show_receipt: z.boolean(),
  show_recipients: z.boolean(),
  is_orphaned: z.boolean().nullable().optional(),
  is_expired: z.boolean().nullable().optional(),
});

/** List-view detail fields (recent receipts). */
const receiptListDetails = z.object({
  type: z.string(),               // "list"
  scope: z.string().nullish(),    // 'org', 'domain', or null (customer default)
  scope_label: z.string().nullish(),
  since: z.number(),
  now: z.number(),                // Unix epoch (UTC seconds)
  has_items: z.boolean(),
  received: z.array(receiptBaseRecord).optional(),
  notreceived: z.array(receiptBaseRecord).optional(),
});

/** Record shape for list items (matches receiptRecordsSchema). */
const receiptListRecord = receiptBaseRecord.extend({
  show_recipients: z.boolean(),
});

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
