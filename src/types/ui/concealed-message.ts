// src/types/ui/concealed-message.ts

/**
 * Minimal data stored in sessionStorage for guest users' recent secrets.
 * Intentionally minimal to reduce attack surface and storage footprint.
 */
export interface ConcealedMessage {
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
}
