// src/schemas/models/receipt.ts

import { createModelSchema } from '@/schemas/models/base';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

/**
 * @fileoverview Receipt schema with unified transformations
 *
 * Key improvements:
 * 1. Unified transformation layer using base transforms
 * 2. Clearer type flow from API to frontend
 * 3. Maintained existing functionality
 *
 * Validation Rules:
 * - Boolean fields come as strings from Ruby/Redis ('true'/'false')
 * - Dates come as UTC strings or timestamps
 * - State field is validated against enum
 * - Optional fields explicitly marked
 */

/**
 * Receipt state enum matching Ruby model
 *
 * Using const object pattern over enum because:
 * 1. Produces simpler runtime code (just a plain object vs IIFE)
 * 2. Better tree-shaking since values can be inlined
 * 3. Works naturally with Zod's z.enum() which expects string literals
 * 4. More flexible for runtime operations (Object.keys(), etc.)
 * 5. Matches idiomatic TypeScript patterns for string-based enums
 */
export const ReceiptState = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  EXPIRED: 'expired',
  ORPHANED: 'orphaned',
} as const;

export type ReceiptState = (typeof ReceiptState)[keyof typeof ReceiptState];

// Create a reusable schema for the state
export const receiptStateSchema = z.enum(Object.values(ReceiptState) as [string, ...string[]]);

// Common base schema for all receipt records
export const receiptBaseSchema = createModelSchema({
  key: z.string(),
  shortid: z.string(),
  secret_shortid: z.string().optional(),
  recipients: z.array(z.string()).or(z.string()).nullable().optional(),
  share_domain: z.string().nullable().optional(),
  secret_ttl: transforms.fromString.number,
  receipt_ttl: transforms.fromString.number,
  lifespan: transforms.fromString.number,
  state: receiptStateSchema,
  created: transforms.fromNumber.secondsToDate,
  updated: transforms.fromNumber.secondsToDate,
  has_passphrase: z.boolean().optional(),
  shared: transforms.fromString.dateNullable.optional(),
  received: transforms.fromString.dateNullable.optional(),
  burned: transforms.fromString.dateNullable.optional(),
  viewed: transforms.fromString.dateNullable.optional(),
  // There is no "expired" time field as a time stamp that is set when the
  // receipt expires. We calculate expiration based on the lifespan (TTL).
  // of the secret.
  //
  // There is no "orphaned" time field. We use updated. To be orphaned is an
  // exceptional case and it's not something we specifically control. Unlike
  // burning or receiving which are linked to user actions, we don't know
  // when the receipt got into an orphaned state; only when we flagged it.
  is_viewed: transforms.fromString.boolean,
  is_received: transforms.fromString.boolean,
  is_burned: transforms.fromString.boolean,
  is_destroyed: transforms.fromString.boolean,
  is_expired: transforms.fromString.boolean,
  is_orphaned: transforms.fromString.boolean,
});

// Receipt shape in single record view
export const receiptSchema = receiptBaseSchema.merge(
  z.object({
    secret_identifier: z.string().nullish().optional(),
    secret_shortid: z.string().nullish().optional(),
    key: z.string().nullish().optional(),
    secret_state: receiptStateSchema.nullish().optional(),
    natural_expiration: z.string(),
    expiration: transforms.fromNumber.secondsToDate,
    expiration_in_seconds: transforms.fromString.number,
    share_path: z.string(),
    burn_path: z.string(),
    receipt_path: z.string(),
    share_url: z.string(),
    receipt_url: z.string(),
    burn_url: z.string(),
    identifier: z.string(),
  })
);

// The details for each record in single record details
export const receiptDetailsSchema = z.object({
  type: z.literal('record'),
  display_lines: transforms.fromString.number,
  no_cache: transforms.fromString.boolean,
  secret_realttl: z.number().nullable().optional(),
  view_count: transforms.fromString.number.nullable(),
  has_passphrase: transforms.fromString.boolean,
  can_decrypt: transforms.fromString.boolean,
  secret_value: z.string().nullable().optional(),
  show_secret: transforms.fromString.boolean,
  show_secret_link: transforms.fromString.boolean,
  show_receipt_link: transforms.fromString.boolean,
  show_receipt: transforms.fromString.boolean,
  show_recipients: transforms.fromString.boolean,
  is_orphaned: transforms.fromString.boolean.nullable().optional(),
  is_expired: transforms.fromString.boolean.nullable().optional(),
});

// Export types
export type Receipt = z.infer<typeof receiptSchema>;
export type ReceiptDetails = z.infer<typeof receiptDetailsSchema>;

export function isValidReceiptState(state: string): state is ReceiptState {
  return Object.values(ReceiptState).includes(state as ReceiptState);
}

/**
 * CHANGELOG
 * ═══════════════════════
 *
 * [2025-03-03] FEATURE
 * ────────────────────────
 * Added new fields:
 * - secret_ttl: number
 * - receipt_ttl: number
 * - lifespan: number
 *
 * transform:
 *   All use transforms.fromString.number
 *
 * why: Added TTL and lifespan tracking to receipt records for consistent time-based operations
 *
 * [2026-01-11] RENAME
 * ────────────────────────
 * Renamed from metadata.ts to receipt.ts
 * - MetadataState -> ReceiptState
 * - Metadata -> Receipt
 * - MetadataDetails -> ReceiptDetails
 * - metadataStateSchema -> receiptStateSchema
 * - metadataBaseSchema -> receiptBaseSchema
 * - metadataSchema -> receiptSchema
 * - metadataDetailsSchema -> receiptDetailsSchema
 * - isValidMetadataState -> isValidReceiptState
 */
