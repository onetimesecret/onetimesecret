// src/schemas/shapes/v3/receipt.ts
//
// V3 wire-format shapes for receipts.
// Derives from contracts, adding V3-specific timestamp transforms (number → Date).

import {
    ReceiptState,
    isValidReceiptState,
    receiptBaseCanonical,
    receiptCanonical,
    receiptDetailsCanonical,
    receiptListCanonical,
    receiptListDetailsCanonical,
    receiptStateSchema,
    receiptStateValues,
} from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 state re-exports (canonical values only — no deprecated aliases)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 receipt state values — canonical only, no deprecated aliases.
 *
 * V3 is the clean API. Deprecated state values ('received', 'viewed')
 * are NOT included. Use 'revealed' and 'previewed' instead.
 */
export { ReceiptState, isValidReceiptState, receiptStateSchema, receiptStateValues };

// ─────────────────────────────────────────────────────────────────────────────
// V3 wire-format overrides
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides for V3 wire format.
 * V3 sends timestamps as Unix epoch numbers; these transform to Date objects.
 *
 * V3 is the clean API — no deprecated field aliases.
 */
const v3TimestampOverrides = {
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  shared: transforms.fromNumber.toDateNullish,
  previewed: transforms.fromNumber.toDateNullish,
  revealed: transforms.fromNumber.toDateNullish,
  burned: transforms.fromNumber.toDateNullish,
};

/**
 * V3 `recipients`: whenever present, `string[]` or `null` — never the V2
 * comma-joined string, and never an empty array.
 *
 * The shared backend safe_dump emits a String (the obscured addresses joined
 * with ', ', or '' when the secret was never emailed) and V2 is frozen on that
 * shape, so V3 normalizes server-side in `V3::Logic::ReceiptShape`
 * (apps/api/v3/logic/receipt_shape.rb). The string branch is kept here as read
 * tolerance only — recipients is display-only, and a strict reject would null
 * the entire receipt (#3424).
 *
 * Stays `.optional()`: every real V3 receipt carries the key (safe_dump always
 * emits it), so an absent key means a partial/synthetic record and is passed
 * through as absent rather than being materialized as null.
 */
const v3Recipients = z
  .union([z.array(z.string()), z.string()])
  .nullable()
  .transform((value): string[] | null => {
    if (value === null) return null;

    const entries = (Array.isArray(value) ? value : value.split(','))
      .map((entry) => entry.trim())
      .filter((entry) => entry.length > 0);

    return entries.length > 0 ? entries : null;
  })
  .optional();

/**
 * Field overrides shared by every V3 receipt shape.
 *
 * `custid` is omitted (not overridden) — see the `.omit()` calls below. It is a
 * deprecated backend field that new receipts never write; `owner_id` is the
 * canonical creator identifier. V3 strips it from the wire entirely
 * (2026-07-29 API audit, item 5).
 */
const v3ReceiptOverrides = {
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
  recipients: v3Recipients,
};

/** Deprecated fields dropped from every V3 receipt shape. */
const v3DroppedFields = { custid: true } as const;

// ─────────────────────────────────────────────────────────────────────────────
// V3 receipt shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 receipt base schema.
 *
 * Derives from contract, adds V3 timestamp transforms (number → Date).
 * Also applies null → false transform for has_passphrase (null for consumed secrets).
 */
export const receiptBaseSchema = receiptBaseCanonical
  .omit(v3DroppedFields)
  .extend(v3ReceiptOverrides);

/**
 * V3 full receipt schema (single-record view with URLs and expiration).
 */
export const receiptSchema = receiptCanonical.omit(v3DroppedFields).extend({
  ...v3ReceiptOverrides,
  // Nullable: null for a consumed/expired secret (see receiptCanonical, #3424).
  expiration: transforms.fromNumber.toDateNullable,
});

/**
 * V3 receipt details.
 *
 * Adds null → false transforms for nullable boolean fields.
 */
export const receiptDetailsSchema = receiptDetailsCanonical.extend({
  has_passphrase: z.boolean().nullable().transform((v) => v ?? false),
  can_decrypt: z.boolean().nullable().transform((v) => v ?? false),
});

/**
 * V3 receipt list schema (base + show_recipients).
 */
export const receiptListSchema = receiptListCanonical
  .omit(v3DroppedFields)
  .extend(v3ReceiptOverrides);

/**
 * V3 receipt list details.
 *
 * Extends contract with arrays of receipt records for categorized display.
 * Uses receiptListSchema (not receiptBaseSchema) because the API includes show_recipients.
 */
export const receiptListDetailsSchema = receiptListDetailsCanonical.extend({
  revealed_receipts: z.array(receiptListSchema).optional(),
  pending_receipts: z.array(receiptListSchema).optional(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptBase = z.infer<typeof receiptBaseSchema>;
export type Receipt = z.infer<typeof receiptSchema>;
export type ReceiptDetails = z.infer<typeof receiptDetailsSchema>;
export type ReceiptListDetails = z.infer<typeof receiptListDetailsSchema>;
export type ReceiptList = z.infer<typeof receiptListSchema>;
