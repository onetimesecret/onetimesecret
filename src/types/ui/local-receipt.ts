// src/types/ui/local-receipt.ts

/**
 * Minimal data stored in sessionStorage for guest users' recent secrets.
 * Intentionally minimal to reduce attack surface and storage footprint.
 *
 * State terminology follows the Receipt model:
 * - isPreviewed: secret link was accessed (confirmation page shown)
 * - isRevealed: secret content was decrypted/consumed
 * - isBurned: secret was manually destroyed before being revealed
 */
export interface LocalReceipt {
  /** Client-generated unique ID for deduplication */
  id: string;
  /** Full receipt identifier for URL routing (/receipt/{receiptExtid}) */
  receiptExtid: string;
  /** Truncated receipt ID for display (8 chars) */
  receiptShortid: string;
  /** Full secret identifier for share URLs (/secret/{secretExtid}) */
  secretExtid: string;
  /** Truncated secret ID for display (8 chars) */
  secretShortid: string;
  /** Custom domain for share URL construction, null for canonical */
  shareDomain: string | null;
  /** Whether secret requires passphrase to view */
  hasPassphrase: boolean;
  /** TTL in seconds at time of creation */
  ttl: number;
  /** Unix timestamp (ms) when secret was created */
  createdAt: number;
  /** Optional user-defined memo for identifying the secret */
  memo?: string;
  /** Whether the secret link has been accessed (confirmation page shown) */
  isPreviewed?: boolean;
  /** Whether the secret content has been revealed (decrypted/consumed) */
  isRevealed?: boolean;
  /** Whether the secret was burned manually (before being revealed) */
  isBurned?: boolean;
}
