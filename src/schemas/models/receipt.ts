// src/schemas/models/receipt.ts
//
// V2 wire-format schemas for receipts.
// Derives from canonical schemas, adding V2-specific string transforms.
//
// V2 API sends data as Redis-serialized strings; these transforms convert
// to the correct output types.

import {
  receiptBaseCanonical,
  receiptCanonical,
  receiptDetailsCanonical,
  receiptStateSchema as canonicalReceiptStateSchema,
} from '@/schemas/api/canonical/records';
import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * Receipt state enum object.
 *
 * Using const object pattern over enum because:
 * 1. Produces simpler runtime code (just a plain object vs IIFE)
 * 2. Better tree-shaking since values can be inlined
 * 3. Works naturally with Zod's z.enum()
 *
 * STATE TERMINOLOGY MIGRATION:
 *   'viewed'   -> 'previewed'  (link accessed, confirmation shown)
 *   'received' -> 'revealed'   (secret content decrypted/consumed)
 *
 * API sends BOTH old and new fields for backward compatibility.
 * @deprecated VIEWED, RECEIVED, is_viewed, is_received, viewed, received
 *             Use PREVIEWED, REVEALED, is_previewed, is_revealed, previewed, revealed
 */
export const ReceiptState = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  REVEALED: 'revealed',
  BURNED: 'burned',
  VIEWED: 'viewed',
  PREVIEWED: 'previewed',
  EXPIRED: 'expired',
  ORPHANED: 'orphaned',
} as const;

export type ReceiptState = (typeof ReceiptState)[keyof typeof ReceiptState];

// Re-export canonical state schema
export const receiptStateSchema = canonicalReceiptStateSchema;

// ─────────────────────────────────────────────────────────────────────────────
// V2 transform overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 timestamp field overrides.
 * V2 sends timestamps as strings or secondsToDate for created/updated.
 */
const v2TimestampOverrides = {
  created: transforms.fromNumber.secondsToDate,
  updated: transforms.fromNumber.secondsToDate,
  shared: transforms.fromString.dateNullable.optional(),
  received: transforms.fromString.dateNullable.optional(),
  viewed: transforms.fromString.dateNullable.optional(),
  previewed: transforms.fromString.dateNullable.optional(),
  revealed: transforms.fromString.dateNullable.optional(),
  burned: transforms.fromString.dateNullable.optional(),
};

/**
 * V2 boolean field overrides.
 */
const v2BooleanOverrides = {
  is_viewed: transforms.fromString.boolean,
  is_received: transforms.fromString.boolean,
  is_previewed: transforms.fromString.boolean.optional(),
  is_revealed: transforms.fromString.boolean.optional(),
  is_burned: transforms.fromString.boolean,
  is_destroyed: transforms.fromString.boolean,
  is_expired: transforms.fromString.boolean,
  is_orphaned: transforms.fromString.boolean,
};

/**
 * V2 number field overrides.
 */
const v2NumberOverrides = {
  secret_ttl: transforms.fromString.number,
  receipt_ttl: transforms.fromString.number,
  lifespan: transforms.fromString.number,
};

// ─────────────────────────────────────────────────────────────────────────────
// Record schemas (V2 wire format: canonical + string transforms)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 receipt base schema.
 *
 * Derives from canonical, adds V2 transforms.
 * Uses createModelSchema to add identifier, created, updated from base.
 */
export const receiptBaseSchema = createModelSchema(
  receiptBaseCanonical.omit({ identifier: true, created: true, updated: true }).extend({
    ...v2TimestampOverrides,
    ...v2BooleanOverrides,
    ...v2NumberOverrides,
  }).shape
);

/**
 * V2 full receipt schema (single-record view with URLs and expiration).
 *
 * Derives from canonical, adds V2 transforms and URL fields.
 */
export const receiptSchema = receiptBaseSchema.merge(
  receiptCanonical
    .pick({
      secret_state: true,
      natural_expiration: true,
      expiration_in_seconds: true,
      share_path: true,
      burn_path: true,
      receipt_path: true,
      share_url: true,
      receipt_url: true,
      burn_url: true,
    })
    .extend({
      secret_identifier: z.string().nullish().optional(),
      secret_shortid: z.string().nullish().optional(),
      key: z.string().nullish().optional(),
      expiration: transforms.fromNumber.secondsToDate,
      expiration_in_seconds: transforms.fromString.number,
      identifier: z.string(),
    })
);

/**
 * V2 receipt details.
 *
 * Derives from canonical, adds V2 transforms.
 */
export const receiptDetailsSchema = receiptDetailsCanonical.extend({
  display_lines: transforms.fromString.number,
  no_cache: transforms.fromString.boolean,
  view_count: transforms.fromString.number.nullable(),
  has_passphrase: transforms.fromString.boolean,
  can_decrypt: transforms.fromString.boolean,
  show_secret: transforms.fromString.boolean,
  show_secret_link: transforms.fromString.boolean,
  show_receipt_link: transforms.fromString.boolean,
  show_receipt: transforms.fromString.boolean,
  show_recipients: transforms.fromString.boolean,
  is_orphaned: transforms.fromString.boolean.nullable().optional(),
  is_expired: transforms.fromString.boolean.nullable().optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type Receipt = z.infer<typeof receiptSchema>;
export type ReceiptDetails = z.infer<typeof receiptDetailsSchema>;

export function isValidReceiptState(state: string): state is ReceiptState {
  return Object.values(ReceiptState).includes(state as ReceiptState);
}
