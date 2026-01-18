// src/utils/status.ts

import { ReceiptState, isValidReceiptState } from '@/schemas/models';
import type { Composer } from 'vue-i18n';

/**
 * DisplayStatus type for UI rendering
 *
 * STATE TERMINOLOGY MIGRATION:
 *   'viewed'   -> 'previewed'  (link accessed, confirmation shown)
 *   'received' -> 'revealed'   (secret content decrypted/consumed)
 *
 * Legacy values (viewed, received) retained for backward compatibility
 * during transition period. Prefer new canonical values (previewed, revealed).
 */
export type DisplayStatus =
  | 'new'
  | 'unread'
  | 'viewed'      // @deprecated - use 'previewed'
  | 'previewed'   // NEW: link accessed, confirmation shown
  | 'burned'
  | 'received'    // @deprecated - use 'revealed'
  | 'revealed'    // NEW: secret content decrypted/consumed
  | 'expiring_soon'
  | 'orphaned'
  | 'expired';

/**
 * State to display status mapping.
 * Maps both new canonical states and legacy aliases to display values.
 */
const STATE_TO_DISPLAY: Record<string, DisplayStatus> = {
  [ReceiptState.NEW]: 'new',
  [ReceiptState.SHARED]: 'new',
  [ReceiptState.PREVIEWED]: 'previewed',
  [ReceiptState.VIEWED]: 'previewed',      // legacy alias
  [ReceiptState.REVEALED]: 'revealed',
  [ReceiptState.RECEIVED]: 'revealed',     // legacy alias
  [ReceiptState.BURNED]: 'burned',
  [ReceiptState.ORPHANED]: 'orphaned',
  [ReceiptState.EXPIRED]: 'expired',
};

/**
 * Maps the given state to UI display status.
 *
 * The only cases where we might need different names are when:
 *
 * 1. We need a more user-friendly display term
 * 2. We need to represent a composite state (like expiring_soon
 *    which combines state with time).
 */
export function getDisplayStatus(
  state: ReceiptState,
  expiresIn?: number
): DisplayStatus {
  if (!state || !isValidReceiptState(state)) {
    return 'orphaned';
  }

  // Check expiring soon first (if active)
  if (
    state === ReceiptState.NEW &&
    typeof expiresIn === 'number' &&
    expiresIn < 1800
  ) {
    return 'expiring_soon';
  }

  return STATE_TO_DISPLAY[state] ?? 'expired';
}

/**
 * Get status display text and description
 */
export function getStatusText(status: DisplayStatus, t: Composer['t']) {
  return {
    text: t(`web.STATUS.${status}`),
    description: t(`web.STATUS.${status}_description`),
  };
}
