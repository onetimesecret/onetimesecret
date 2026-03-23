// src/schemas/shapes/v1/receipt.ts
//
// V1 wire-format schemas for receipts (legacy "metadata" terminology).
//
// V1 API sends data with v0.23.x field names and type contracts:
// - metadata_key/secret_key (not identifier/secret_identifier)
// - metadata_ttl/metadata_url (not receipt_ttl/receipt_url)
// - received/viewed (not revealed/previewed)
// - passphrase_required (not has_passphrase)
// - All timestamps and TTLs as integers (Unix epoch seconds)
// - custid as email string (not objid UUID)
//
// Field Mapping (V1 wire -> internal):
//   metadata_key     -> identifier
//   secret_key       -> secret_identifier
//   metadata_ttl     -> receipt_ttl (actual seconds remaining)
//   metadata_url     -> receipt_url
//   passphrase_required -> has_passphrase
//   recipient        -> recipients (singular to plural)
//   value            -> secret_value
//   received         -> revealed (timestamp fallback)
//   viewed           -> previewed (state translation)
//
// State Mapping (V1 wire <- internal):
//   new      <- new, shared
//   received <- received, revealed
//   viewed   <- viewed, previewed
//   burned   <- burned
//   expired  <- expired
//   orphaned <- orphaned

import { z } from 'zod';

// ---------------------------------------------------------------------------
// V1 state values (v0.23.x vocabulary)
// ---------------------------------------------------------------------------

/**
 * V1 receipt state values -- v0.23.x vocabulary.
 *
 * V1 uses the original state names before the terminology migration:
 * - "received" instead of "revealed"
 * - "viewed" instead of "previewed"
 * - No "shared" state (mapped to "new")
 */
export const v1ReceiptStateValues = [
  'new',
  'received', // v0.24 calls this "revealed"
  'viewed', // v0.24 calls this "previewed"
  'burned',
  'expired',
  'orphaned',
] as const;

export type V1ReceiptState = (typeof v1ReceiptStateValues)[number];

/**
 * V1 receipt state enum object for runtime checks.
 */
export const V1ReceiptState = {
  NEW: 'new',
  RECEIVED: 'received', // v0.24: REVEALED
  VIEWED: 'viewed', // v0.24: PREVIEWED
  BURNED: 'burned',
  EXPIRED: 'expired',
  ORPHANED: 'orphaned',
} as const;

export const v1ReceiptStateSchema = z.enum(v1ReceiptStateValues);

/**
 * Type guard for V1 receipt state validation.
 */
export function isValidV1ReceiptState(state: string): state is V1ReceiptState {
  return v1ReceiptStateValues.includes(state as V1ReceiptState);
}

// ---------------------------------------------------------------------------
// V1 receipt schema (legacy "metadata" wire format)
// ---------------------------------------------------------------------------

/**
 * V1 receipt record schema.
 *
 * This reflects the exact wire format returned by the V1 API,
 * using v0.23.x field names and type contracts.
 *
 * Type contracts (enforced by coerce_v1_types on backend):
 * - created, updated, received: Integer (Unix epoch seconds)
 * - ttl, metadata_ttl, secret_ttl: Integer (seconds)
 * - passphrase_required: boolean (true/false)
 * - recipient: Array of strings
 * - custid, metadata_key, secret_key, state, share_domain, value: String
 *
 * Note: V1 API uses additive field mapping -- it emits BOTH old and new
 * field names for migration support. This schema validates the primary
 * (legacy) field names; new names are optional aliases.
 */
export const v1ReceiptSchema = z.object({
  // Primary V1 fields (v0.23.x names)
  custid: z.string(), // Email address (not UUID); "anon" for anonymous
  metadata_key: z.string(), // Receipt identifier
  secret_key: z.string().optional(), // Secret identifier (omitted when state=received)
  state: v1ReceiptStateSchema,

  // Timestamps as integers (Unix epoch seconds)
  created: z.number().int(),
  updated: z.number().int(),
  received: z.number().int().optional(), // Only present when state=received

  // TTL fields as integers (seconds)
  ttl: z.number().int(), // Original requested TTL
  metadata_ttl: z.number().int(), // Actual seconds remaining on receipt
  secret_ttl: z.number().int().nullable().optional(), // Actual seconds remaining on secret

  // URLs
  metadata_url: z.string().nullable().optional(), // Full URL to receipt page

  // Sharing
  share_domain: z.string(), // Never null; empty string if not set
  recipient: z.array(z.string()), // Always array (even if empty)

  // Security
  passphrase_required: z.boolean().optional(), // Only present if explicitly set

  // Secret value (only in reveal responses)
  value: z.string().optional(),

  // --- Additive V1 aliases (v0.24 names emitted for migration) ---
  // These mirror the primary fields above; clients can use either.
  identifier: z.string().optional(), // Alias for metadata_key
  secret_identifier: z.string().optional(), // Alias for secret_key
  has_passphrase: z.boolean().optional(), // Alias for passphrase_required
  recipients: z.array(z.string()).optional(), // Alias for recipient
  receipt_ttl: z.number().int().optional(), // Alias for metadata_ttl
  receipt_url: z.string().optional(), // Alias for metadata_url
  secret_value: z.string().optional(), // Alias for value
});

/**
 * V1 receipt response wrapper.
 *
 * V1 API responses wrap the receipt in a top-level object.
 * This schema handles the response envelope.
 */
export const v1ReceiptResponseSchema = z.object({
  custid: z.string().optional(),
  metadata: v1ReceiptSchema.optional(), // Legacy name for receipt
  shrimp: z.string().optional(), // CSRF token
});

// ---------------------------------------------------------------------------
// Type exports
// ---------------------------------------------------------------------------

export type V1Receipt = z.infer<typeof v1ReceiptSchema>;
export type V1ReceiptResponse = z.infer<typeof v1ReceiptResponseSchema>;
