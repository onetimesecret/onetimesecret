// src/schemas/ui/local-receipt.ts

/**
 * LocalReceipt Zod schemas and derived types
 *
 * Schemas are the source of truth for sessionStorage-persisted receipt data.
 * Types are inferred from schemas using z.infer<>.
 *
 * Runtime validation is critical here because data comes from sessionStorage
 * which could be corrupted, tampered with, or from an older app version.
 */

import { z } from 'zod';

/**
 * LocalReceipt schema
 *
 * Minimal data stored in sessionStorage for guest users' recent secrets.
 * Intentionally minimal to reduce attack surface and storage footprint.
 *
 * State terminology follows the Receipt model:
 * - isPreviewed: secret link was accessed (confirmation page shown)
 * - isRevealed: secret content was decrypted/consumed
 * - isBurned: secret was manually destroyed before being revealed
 */
export const localReceiptSchema = z.object({
  /** Client-generated unique ID for deduplication */
  id: z.string(),
  /** Full receipt identifier for URL routing (/receipt/{receiptExtid}) */
  receiptExtid: z.string(),
  /** Truncated receipt ID for display (8 chars) */
  receiptShortid: z.string(),
  /** Full secret identifier for share URLs (/secret/{secretExtid}) */
  secretExtid: z.string(),
  /** Truncated secret ID for display (8 chars) */
  secretShortid: z.string(),
  /** Custom domain for share URL construction, null for canonical */
  shareDomain: z.string().nullable(),
  /** Whether secret requires passphrase to view */
  hasPassphrase: z.boolean(),
  /** TTL in seconds at time of creation */
  ttl: z.number(),
  /** Unix timestamp (ms) when secret was created */
  createdAt: z.number(),
  /** Optional user-defined memo for identifying the secret */
  memo: z.string().optional(),
  /** Whether the secret link has been accessed (confirmation page shown) */
  isPreviewed: z.boolean().optional(),
  /** Whether the secret content has been revealed (decrypted/consumed) */
  isRevealed: z.boolean().optional(),
  /** Whether the secret was burned manually (before being revealed) */
  isBurned: z.boolean().optional(),
});

export type LocalReceipt = z.infer<typeof localReceiptSchema>;

/**
 * Array of LocalReceipts for storage validation
 */
export const localReceiptsArraySchema = z.array(localReceiptSchema);

export type LocalReceiptsArray = z.infer<typeof localReceiptsArraySchema>;

/**
 * GuestReceiptRecord schema
 *
 * Single record from the batch receipts status API response.
 * Fields match Receipt safe_dump output from backend.
 */
export const guestReceiptRecordSchema = z.object({
  /** Full receipt identifier for matching */
  identifier: z.string(),
  /** Receipt shortid (first 8 chars) */
  shortid: z.string(),
  /** Secret shortid for cross-reference if needed */
  secret_shortid: z.string(),
  is_previewed: z.boolean().optional(),
  is_revealed: z.boolean().optional(),
  is_burned: z.boolean().optional(),
  is_expired: z.boolean().optional(),
  is_destroyed: z.boolean().optional(),
});

export type GuestReceiptRecord = z.infer<typeof guestReceiptRecordSchema>;

/**
 * GuestReceiptsResponse schema
 *
 * Response from the batch receipts status API (POST /api/v3/guest/receipts).
 */
export const guestReceiptsResponseSchema = z.object({
  records: z.array(guestReceiptRecordSchema),
  count: z.number(),
});

export type GuestReceiptsResponse = z.infer<typeof guestReceiptsResponseSchema>;
