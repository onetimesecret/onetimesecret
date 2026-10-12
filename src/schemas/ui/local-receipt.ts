// src/schemas/ui/local-receipt.ts

/**
 * LocalReceipt Zod schemas and derived types
 *
 * Schemas are the source of truth for sessionStorage-persisted receipt data
 * (storedLocalReceiptSchema) and the in-memory record built on it
 * (localReceiptSchema).
 * Types are inferred from schemas using z.infer<>.
 *
 * Runtime validation is critical here because data comes from sessionStorage
 * which could be corrupted, tampered with, or from an older app version.
 */

import { z } from 'zod';

/**
 * StoredLocalReceipt schema
 *
 * The part of a guest's recent-secret record that is persisted to
 * sessionStorage: enough to list the receipt, refresh its status and re-open
 * it at /receipt/{receiptExtid}. Intentionally minimal to reduce attack
 * surface and storage footprint.
 *
 * The secret identifier (the share link's bearer key) is deliberately absent
 * (RISK-2026-08-14-M10): it lives only on the in-memory record for the page
 * that created it. Entries written by older versions still carry
 * `secretExtid`; parsing strips it (z.object drops unknown keys), so those
 * entries load and the next write leaves it out.
 *
 * `receiptExtid` is still a capability: a standard receipt's payload can
 * carry the share link and its secret identifier (Receipt#shows_share_link?
 * in lib/onetime/models/receipt.rb). Only entries whose secret has not
 * expired are persisted.
 *
 * State terminology follows the Receipt model:
 * - isPreviewed: secret link was accessed (confirmation page shown)
 * - isRevealed: secret content was decrypted/consumed
 * - isBurned: secret was manually destroyed before being revealed
 */
export const storedLocalReceiptSchema = z.object({
  /** Client-generated unique ID for deduplication */
  id: z.string(),
  /** Full receipt identifier for URL routing (/receipt/{receiptExtid}) */
  receiptExtid: z.string(),
  /** Truncated receipt ID for display (8 chars) */
  receiptShortid: z.string(),
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

export type StoredLocalReceipt = z.infer<typeof storedLocalReceiptSchema>;

/**
 * Array of StoredLocalReceipts for storage validation
 */
export const storedLocalReceiptsArraySchema = z.array(storedLocalReceiptSchema);

/**
 * LocalReceipt schema
 *
 * The in-memory record: the stored fields plus the secret identifier, which
 * is present only for receipts created during the current page lifecycle.
 * Records restored from sessionStorage have no `secretExtid`; the UI then
 * links to the receipt page, which shows the share link, instead of building
 * it locally.
 */
export const localReceiptSchema = storedLocalReceiptSchema.extend({
  /** Full secret identifier for share URLs (/secret/{secretExtid}); memory only */
  secretExtid: z.string().optional(),
});

export type LocalReceipt = z.infer<typeof localReceiptSchema>;

/**
 * Array of LocalReceipts
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
