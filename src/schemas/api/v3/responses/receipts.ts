// src/schemas/api/v3/responses/receipts.ts
//
// V3 JSON wire-format schemas for receipt endpoints.
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas
// ─────────────────────────────────────────────────────────────────────────────

const receiptStateValues = [
  'new', 'shared', 'received', 'revealed', 'burned',
  'viewed', 'previewed', 'expired', 'orphaned',
] as const;

/** Base receipt fields shared between list and detail views. */
export const receiptBaseRecord = z.object({
  identifier: z.string(),
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  key: z.string(),
  shortid: z.string(),
  secret_identifier: z.string().nullish(),
  secret_shortid: z.string().optional(),
  recipients: z.array(z.string()).or(z.string()).nullable().optional(),
  share_domain: z.string().nullable().optional(),
  secret_ttl: z.number(),         // seconds (duration, not timestamp)
  receipt_ttl: z.number(),        // seconds
  lifespan: z.number(),           // seconds
  state: z.enum(receiptStateValues),
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false), // null/undefined for consumed secrets

  // Timestamp fields (Unix epoch → Date, or null)
  shared: transforms.fromNumber.toDateNullish,
  received: transforms.fromNumber.toDateNullish,     // @deprecated — use revealed
  viewed: transforms.fromNumber.toDateNullish,       // @deprecated — use previewed
  previewed: transforms.fromNumber.toDateNullish,
  revealed: transforms.fromNumber.toDateNullish,
  burned: transforms.fromNumber.toDateNullish,

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
  secret_state: z.enum(receiptStateValues).nullish(),
  natural_expiration: z.string(),
  expiration: transforms.fromNumber.toDate,
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
  has_passphrase: z.boolean().nullable().transform((v) => v ?? false), // null when secret is consumed/destroyed
  can_decrypt: z.boolean().nullable().transform((v) => v ?? false),   // null when secret is consumed/destroyed
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
