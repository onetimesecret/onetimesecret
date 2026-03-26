// src/schemas/shapes/v2/receipt.ts
//
// V2 wire-format schemas for receipts.
// Derives from canonical schemas, adding V2-specific string transforms.
//
// V2 API sends data as Redis-serialized strings; these transforms convert
// to the correct output types.

import {
  ReceiptState as CanonicalReceiptState,
  receiptStateValues as canonicalStateValues,
  receiptBaseCanonical,
  receiptCanonical,
  receiptDetailsCanonical,
  receiptListDetailsCanonical,
} from '@/schemas/contracts';
import { createModelSchema } from '@/schemas/shapes/v2/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V2 state values (includes deprecated aliases for backward compatibility)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 receipt state values — extends canonical with deprecated aliases.
 */
export const receiptStateValues = [
  ...canonicalStateValues,
  'received', // @deprecated — use 'revealed'
  'viewed', // @deprecated — use 'previewed'
] as const;

export type ReceiptState = (typeof receiptStateValues)[number];

/**
 * V2 receipt state enum object — extends canonical with deprecated aliases.
 */
export const ReceiptState = {
  ...CanonicalReceiptState,
  RECEIVED: 'received', // @deprecated — use REVEALED
  VIEWED: 'viewed', // @deprecated — use PREVIEWED
} as const;

export const receiptStateSchema = z.enum(receiptStateValues);

/**
 * Type guard for V2 receipt state validation (includes deprecated values).
 */
export function isValidReceiptState(state: string): state is ReceiptState {
  return receiptStateValues.includes(state as ReceiptState);
}

// ─────────────────────────────────────────────────────────────────────────────
// V2 transform overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 timestamp field overrides.
 *
 * created/updated come as numbers (Unix epoch seconds) from the backend.
 * Other timestamps (shared, received, etc.) come as strings.
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
// Record schemas (V2 wire format: canonical + transforms)
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
// List schemas (V2 wire format)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V2 receipt list schema (base + show_recipients).
 *
 * Used for individual records in the /receipt/recent list response.
 */
export const receiptListSchema = receiptBaseSchema.extend({
  show_recipients: transforms.fromString.boolean,
});

/**
 * V2 receipt list details.
 *
 * Metadata for the list response with categorized receipt arrays.
 * Backend sends `revealed_receipts` and `pending_receipts` (renamed from
 * the old `received`/`notreceived` in commit 34681572b).
 */
export const receiptListDetailsSchema = receiptListDetailsCanonical.extend({
  now: transforms.fromString.date,
  has_items: transforms.fromString.boolean,
  revealed_receipts: z.array(receiptListSchema).optional(),
  pending_receipts: z.array(receiptListSchema).optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type Receipt = z.infer<typeof receiptSchema>;
export type ReceiptDetails = z.infer<typeof receiptDetailsSchema>;
export type ReceiptList = z.infer<typeof receiptListSchema>;
export type ReceiptListDetails = z.infer<typeof receiptListDetailsSchema>;
