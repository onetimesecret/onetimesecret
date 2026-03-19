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
} from '@/schemas/contracts';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 timestamp transforms
// ─────────────────────────────────────────────────────────────────────────────

/**
 * Timestamp field overrides for V3 wire format.
 * V3 sends timestamps as Unix epoch numbers; these transform to Date objects.
 */
const v3TimestampOverrides = {
  created: transforms.fromNumber.toDate,
  updated: transforms.fromNumber.toDate,
  shared: transforms.fromNumber.toDateNullish,
  received: transforms.fromNumber.toDateNullish,
  viewed: transforms.fromNumber.toDateNullish,
  previewed: transforms.fromNumber.toDateNullish,
  revealed: transforms.fromNumber.toDateNullish,
  burned: transforms.fromNumber.toDateNullish,
};

// ─────────────────────────────────────────────────────────────────────────────
// V3 receipt shapes
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 receipt base record.
 *
 * Derives from contract, adds V3 timestamp transforms (number → Date).
 * Also applies null → false transform for has_passphrase (null for consumed secrets).
 */
export const receiptBaseRecord = receiptBaseCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
});

/**
 * V3 full receipt record (single-record view with URLs and expiration).
 */
export const receiptRecord = receiptCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
  expiration: transforms.fromNumber.toDate,
});

/**
 * V3 receipt details.
 *
 * Adds null → false transforms for nullable boolean fields.
 */
export const receiptDetails = receiptDetailsCanonical.extend({
  has_passphrase: z.boolean().nullable().transform((v) => v ?? false),
  can_decrypt: z.boolean().nullable().transform((v) => v ?? false),
});

/**
 * V3 receipt list details.
 *
 * Extends contract with arrays of receipt records for categorized display.
 */
export const receiptListDetails = receiptListDetailsCanonical.extend({
  received: z.array(receiptBaseRecord).optional(),
  notreceived: z.array(receiptBaseRecord).optional(),
});

/**
 * V3 receipt list record (base + show_recipients).
 */
export const receiptListRecord = receiptListCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

export type ReceiptBaseRecord = z.infer<typeof receiptBaseRecord>;
export type ReceiptRecord = z.infer<typeof receiptRecord>;
export type ReceiptDetails = z.infer<typeof receiptDetails>;
export type ReceiptListDetails = z.infer<typeof receiptListDetails>;
export type ReceiptListRecord = z.infer<typeof receiptListRecord>;
