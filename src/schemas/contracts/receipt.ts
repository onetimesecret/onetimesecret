// src/schemas/contracts/receipt.ts
//
// Canonical receipt record schema — field names and output types only.
// Version-specific schemas (V2, V3) extend this with wire-format transforms.
//
// This schema owns the field contract. V2/V3 own the encoding.

/**
 * Receipt record contracts defining field names and output types.
 *
 * Receipts track the lifecycle of secrets: creation, sharing, viewing,
 * and destruction. These canonical schemas define the "what" (field names
 * and final types) without the "how" (wire-format transforms).
 *
 * Version-specific shapes in `shapes/v2/receipt.ts` and `shapes/v3/receipt.ts`
 * extend these with appropriate transforms for each API version.
 *
 * @module contracts/receipt
 * @category Contracts
 * @see {@link "shapes/v2/receipt"} - V2 wire format with string transforms
 * @see {@link "shapes/v3/receipt"} - V3 wire format with number-to-Date transforms
 */

import { z } from 'zod';

/**
 * Receipt state values as a const tuple.
 *
 * Contracts represent current fields. Shapes represent the wire format and
 * so they are responsible for BOTH old and new values for backward
 * compatibility. If a field for backwards compatibility cannot be derived
 * from the contract fields, then it needs to remain in the contract.
 *
 * @category Contracts
 * @example
 * ```typescript
 * // Use with Zod enum
 * const stateSchema = z.enum(receiptStateValues);
 *
 * // Type narrowing
 * if (receiptStateValues.includes(value as ReceiptState)) {
 *   // value is ReceiptState
 * }
 * ```
 */
export const receiptStateValues = [
  'new',
  'shared',
  // 'received',   // @deprecated — use 'revealed'
  'revealed',
  'burned',
  // 'viewed',     // @deprecated — use 'previewed'
  'previewed',
  'expired',
  'orphaned',
] as const;

export type ReceiptState = (typeof receiptStateValues)[number];

/**
 * Receipt state enum object for runtime state checks.
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
 *
 * @category Contracts
 * @deprecated VIEWED, RECEIVED, is_viewed, is_received, viewed, received -
 *             Use PREVIEWED, REVEALED, is_previewed, is_revealed, previewed, revealed
 *
 * @example
 * ```typescript
 * if (receipt.state === ReceiptState.REVEALED) {
 *   // Secret has been revealed
 * }
 *
 * // Lifecycle progression
 * switch (receipt.state) {
 *   case ReceiptState.NEW:
 *     return 'Created';
 *   case ReceiptState.SHARED:
 *     return 'Shared';
 *   case ReceiptState.REVEALED:
 *     return 'Viewed';
 *   case ReceiptState.BURNED:
 *     return 'Destroyed';
 *   case ReceiptState.EXPIRED:
 *     return 'Expired';
 * }
 * ```
 */
export const ReceiptState = {
  NEW: 'new',
  SHARED: 'shared',
  // RECEIVED: 'received',
  REVEALED: 'revealed',
  BURNED: 'burned',
  // VIEWED: 'viewed',
  PREVIEWED: 'previewed',
  EXPIRED: 'expired',
  ORPHANED: 'orphaned',
} as const;

/**
 * Zod schema for validating receipt state values.
 *
 * @category Contracts
 */
export const receiptStateSchema = z.enum(receiptStateValues);

/**
 * Type guard for runtime receipt state validation.
 *
 * @param state - String to validate
 * @returns True if state is a valid ReceiptState value
 *
 * @category Contracts
 * @example
 * ```typescript
 * const userInput = 'revealed';
 * if (isValidReceiptState(userInput)) {
 *   // userInput is now typed as ReceiptState
 *   console.log(`Valid state: ${userInput}`);
 * }
 * ```
 */
export function isValidReceiptState(state: string): state is ReceiptState {
  return receiptStateValues.includes(state as ReceiptState);
}

/**
 * Canonical receipt base record contract.
 *
 * Defines field names and output types (post-parse).
 * No transforms - those are version-specific in shapes.
 *
 * Receipts are ownership tokens that track a secret's lifecycle:
 * - Timestamps for creation, sharing, viewing, and destruction
 * - TTL fields for expiration management
 * - Boolean flags for state checks in components
 *
 * @category Contracts
 * @see {@link "shapes/v2/receipt".receiptSchema} - V2 wire format
 * @see {@link "shapes/v3/receipt".receiptSchema} - V3 wire format
 *
 * @example
 * ```typescript
 * // Extend in version-specific shapes
 * const receiptBaseV3 = receiptBaseCanonical.extend({
 *   created: transforms.fromNumber.toDate,
 *   updated: transforms.fromNumber.toDate,
 * });
 *
 * // Derive TypeScript type
 * type ReceiptBase = z.infer<typeof receiptBaseCanonical>;
 * ```
 */
export const receiptBaseCanonical = z.object({
  identifier: z.string(),
  key: z.string(),
  shortid: z.string(),
  state: receiptStateSchema,

  // Ownership
  custid: z.string().optional(),
  owner_id: z.string().optional(),

  // Timestamps (all Date output, nullable for unset)
  created: z.date(),
  updated: z.date(),
  shared: z.date().nullable(),
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
  is_previewed: z.boolean(),
  is_revealed: z.boolean(),
  is_burned: z.boolean(),
  is_destroyed: z.boolean(),
  is_expired: z.boolean(),
  is_orphaned: z.boolean(),

  // Optional metadata
  memo: z.string().nullable().optional(),
  kind: z.enum(['generate', 'conceal']).or(z.literal('')).nullable().optional(),
});

/**
 * Canonical full receipt record with URLs and expiration.
 *
 * Single-record view that includes sharing URLs and expiration details
 * for display in the receipt confirmation page.
 *
 * @category Contracts
 * @see {@link receiptBaseCanonical} - Base record without URLs
 *
 * @example
 * ```typescript
 * const receipt = receiptCanonical.parse(apiResponse);
 * console.log(`Share link: ${receipt.share_url}`);
 * console.log(`Expires: ${receipt.natural_expiration}`);
 * ```
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
 * Canonical receipt details contract.
 *
 * Metadata returned alongside receipt records for display logic.
 * Controls visibility of secret content, links, and status indicators.
 *
 * @category Contracts
 * @see {@link "shapes/v2/receipt".receiptDetails} - V2 wire format
 *
 * @example
 * ```typescript
 * const details = receiptDetailsCanonical.parse(apiResponse.details);
 * if (details.show_secret && details.can_decrypt) {
 *   // Display the secret content
 * }
 * ```
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
 * Canonical receipt list details contract.
 *
 * Metadata for paginated receipt list responses.
 *
 * @category Contracts
 *
 * @example
 * ```typescript
 * const listDetails = receiptListDetailsCanonical.parse(apiResponse.details);
 * if (listDetails.has_items) {
 *   // Display the receipt list
 * }
 * ```
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
 * Canonical receipt list record contract.
 *
 * Base receipt extended with `show_recipients` for list display.
 *
 * @category Contracts
 * @see {@link receiptBaseCanonical} - Base record
 *
 * @example
 * ```typescript
 * const receipts = z.array(receiptListCanonical).parse(apiResponse.records);
 * receipts.forEach(receipt => {
 *   console.log(`${receipt.shortid}: ${receipt.state}`);
 * });
 * ```
 */
export const receiptListCanonical = receiptBaseCanonical.extend({
  show_recipients: z.boolean(),
});

// ─────────────────────────────────────────────────────────────────────────────
// Type exports
// ─────────────────────────────────────────────────────────────────────────────

/** TypeScript type for base receipt record. */
export type ReceiptBaseCanonical = z.infer<typeof receiptBaseCanonical>;

/** TypeScript type for full receipt record with URLs. */
export type ReceiptCanonical = z.infer<typeof receiptCanonical>;

/** TypeScript type for receipt details metadata. */
export type ReceiptDetailsCanonical = z.infer<typeof receiptDetailsCanonical>;

/** TypeScript type for receipt list details metadata. */
export type ReceiptListDetailsCanonical = z.infer<typeof receiptListDetailsCanonical>;

/** TypeScript type for receipt list record. */
export type ReceiptListCanonical = z.infer<typeof receiptListCanonical>;
