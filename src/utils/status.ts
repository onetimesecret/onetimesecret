// src/utils/status.ts

import { ReceiptState, isValidReceiptState } from '@/schemas/models';
import type { Composer } from 'vue-i18n';

export type DisplayStatus =
  | 'new'
  | 'unread'
  | 'viewed'
  | 'burned'
  | 'received'
  | 'expiring_soon'
  | 'orphaned'
  | 'expired';

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

  switch (state) {
    case ReceiptState.NEW:
    case ReceiptState.SHARED:
      return 'new'; // Secret created/shared but not accessed

    case ReceiptState.VIEWED:
      return 'viewed'; // Secret accessed but not revealed

    case ReceiptState.RECEIVED:
      return 'received'; // Secret revealed/decrypted

    case ReceiptState.BURNED:
      return 'burned';

    // case ReceiptState.ORPHANED:
    //   return 'orphaned'; // Secret in invalid state

    default:
      return 'expired';
  }
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
