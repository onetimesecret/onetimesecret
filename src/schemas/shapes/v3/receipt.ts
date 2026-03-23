// src/schemas/shapes/v3/receipt.ts
//
// V3 wire-format shapes for receipts.
// Derives from contracts, adding V3-specific timestamp transforms (number → Date).

import {
  receiptBaseCanonical,
  receiptCanonical,
  receiptDetailsCanonical,
  receiptListDetailsCanonical,
  receiptListCanonical,
  receiptStateValues,
  receiptStateSchema,
  ReceiptState,
  isValidReceiptState,
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
export { receiptStateValues, receiptStateSchema, ReceiptState, isValidReceiptState };

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

// ─────────────────────────────────────────────────────────────────────────────
// V3 receipt shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 receipt base schema.
 *
 * Derives from contract, adds V3 timestamp transforms (number → Date).
 * Also applies null → false transform for has_passphrase (null for consumed secrets).
 */
export const receiptBaseSchema = receiptBaseCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
});

/**
 * V3 full receipt schema (single-record view with URLs and expiration).
 */
export const receiptSchema = receiptCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
  expiration: transforms.fromNumber.toDate,
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
export const receiptListSchema = receiptListCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
});

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
