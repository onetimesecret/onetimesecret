// src/schemas/api/canonical/records/receipt.ts
//
// Canonical receipt record schema — field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

import { z } from 'zod';

/**
 * Receipt state values.
 *
 * STATE TERMINOLOGY MIGRATION:
 *   'viewed'   -> 'previewed'  (link accessed, confirmation shown)
 *   'received' -> 'revealed'   (secret content decrypted/consumed)
 *
 * API sends BOTH old and new values for backward compatibility.
 */
export const receiptStateValues = [
  'new',
  'shared',
  'received',   // @deprecated — use 'revealed'
  'revealed',
  'burned',
  'viewed',     // @deprecated — use 'previewed'
  'previewed',
  'expired',
  'orphaned',
] as const;

export type ReceiptState = (typeof receiptStateValues)[number];

export const receiptStateSchema = z.enum(receiptStateValues);

/**
 * Canonical receipt base record.
 *
 * Defines field names and output types (post-parse).
 * No transforms — those are version-specific.
 */
export const receiptBaseCanonical = z.object({
  identifier: z.string(),
  key: z.string(),
  shortid: z.string(),
  state: receiptStateSchema,

  // Timestamps (all Date output, nullable for unset)
  created: z.date(),
  updated: z.date(),
  shared: z.date().nullable(),
  received: z.date().nullable(),      // @deprecated — use revealed
  viewed: z.date().nullable(),        // @deprecated — use previewed
  previewed: z.date().nullable(),
  revealed: z.date().nullable(),
  burned: z.date().nullable(),

  // TTL fields (all numbers, seconds)
  secret_ttl: z.number(),
  receipt_ttl: z.number(),
  lifespan: z.number(),

  // Related secret
  secret_shortid: z.string().optional(),
  secret_identifier: z.string().nullish(),

  // Recipients and sharing
  recipients: z.array(z.string()).or(z.string()).nullable().optional(),
  share_domain: z.string().nullable().optional(),

  // Boolean status flags
  has_passphrase: z.boolean().nullish(),
  is_viewed: z.boolean(),             // @deprecated — use is_previewed
  is_received: z.boolean(),           // @deprecated — use is_revealed
  is_previewed: z.boolean().optional(),
  is_revealed: z.boolean().optional(),
  is_burned: z.boolean(),
  is_destroyed: z.boolean(),
  is_expired: z.boolean(),
  is_orphaned: z.boolean(),

  // Optional metadata
  memo: z.string().nullable().optional(),
  kind: z.enum(['generate', 'conceal']).or(z.literal('')).nullable().optional(),
});

/**
 * Canonical full receipt record (single-record view with URLs and expiration).
 */
export const receiptCanonical = receiptBaseCanonical.extend({
  secret_state: receiptStateSchema.nullish(),
  natural_expiration: z.string(),
  expiration: z.date(),
  expiration_in_seconds: z.number(),
  share_path: z.string(),
  burn_path: z.string(),
  receipt_path: z.string(),
  share_url: z.string(),
  receipt_url: z.string(),
  burn_url: z.string(),
});

/**
 * Canonical receipt details (metadata alongside the record).
 */
export const receiptDetailsCanonical = z.object({
  type: z.literal('record'),
  display_lines: z.number(),
  no_cache: z.boolean(),
  secret_realttl: z.number().nullable().optional(),
  view_count: z.number().nullable(),
  has_passphrase: z.boolean().nullable(),
  can_decrypt: z.boolean().nullable(),
  secret_value: z.string().nullable().optional(),
  show_secret: z.boolean(),
  show_secret_link: z.boolean(),
  show_receipt_link: z.boolean(),
  show_receipt: z.boolean(),
  show_recipients: z.boolean(),
  is_orphaned: z.boolean().nullable().optional(),
  is_expired: z.boolean().nullable().optional(),
});

/**
 * Canonical receipt list details.
 */
export const receiptListDetailsCanonical = z.object({
  type: z.string(),
  scope: z.string().nullish(),
  scope_label: z.string().nullish(),
  since: z.number(),
  now: z.number(),
  has_items: z.boolean(),
});

/**
 * Canonical receipt list record (base + show_recipients).
 */
export const receiptListCanonical = receiptBaseCanonical.extend({
  show_recipients: z.boolean(),
});

// Type exports
export type ReceiptBaseCanonical = z.infer<typeof receiptBaseCanonical>;
export type ReceiptCanonical = z.infer<typeof receiptCanonical>;
export type ReceiptDetailsCanonical = z.infer<typeof receiptDetailsCanonical>;
export type ReceiptListDetailsCanonical = z.infer<typeof receiptListDetailsCanonical>;
export type ReceiptListCanonical = z.infer<typeof receiptListCanonical>;
