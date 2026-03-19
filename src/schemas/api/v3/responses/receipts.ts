// src/schemas/api/v3/responses/receipts.ts
//
// V3 JSON wire-format schemas for receipt endpoints.
// Derives from canonical schemas, adding V3-specific timestamp transforms.
//
// Timestamps use transforms.fromNumber.toDate so that .parse() returns
// Date objects for the frontend while io:"input" still documents them
// as numbers in OpenAPI.

import { createApiResponseSchema, createApiListResponseSchema } from '@/schemas/api/base';
import {
  receiptBaseCanonical,
  receiptCanonical,
  receiptDetailsCanonical,
  receiptListDetailsCanonical,
  receiptListCanonical,
} from '@/schemas/api/canonical/records';
import { transforms } from '@/schemas/transforms';
import { z } from 'zod';

// ─────────────────────────────────────────────────────────────────────────────
// V3 timestamp transforms for receipts
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
// Record schemas (V3 wire format: canonical + timestamp transforms)
// ─────────────────────────────────────────────────────────────────────────────

/**
 * V3 receipt base record.
 *
 * Derives from canonical, adds V3 timestamp transforms (number → Date).
 * Also applies null → false transform for has_passphrase (null for consumed secrets).
 */
export const receiptBaseRecord = receiptBaseCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
});

/**
 * V3 full receipt record (single-record view with URLs and expiration).
 */
const receiptRecord = receiptCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
  expiration: transforms.fromNumber.toDate,
});

/**
 * V3 receipt details.
 *
 * Adds null → false transforms for nullable boolean fields.
 */
const receiptDetails = receiptDetailsCanonical.extend({
  has_passphrase: z.boolean().nullable().transform((v) => v ?? false),
  can_decrypt: z.boolean().nullable().transform((v) => v ?? false),
});

/**
 * V3 receipt list details.
 *
 * Extends canonical with arrays of receipt records for categorized display.
 */
const receiptListDetails = receiptListDetailsCanonical.extend({
  received: z.array(receiptBaseRecord).optional(),
  notreceived: z.array(receiptBaseRecord).optional(),
});

/**
 * V3 receipt list record (base + show_recipients).
 */
const receiptListRecord = receiptListCanonical.extend({
  ...v3TimestampOverrides,
  has_passphrase: z.boolean().nullish().transform((v) => v ?? false),
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
