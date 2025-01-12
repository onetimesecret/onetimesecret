// src/utils/status.ts

import { type Metadata } from '@/schemas/models';
import type { Composer } from 'vue-i18n';

export type DisplayStatus =
  | 'active'
  | 'received'
  | 'burned'
  | 'destroyed'
  | 'expiring-soon'
  | 'processing'
  | 'secured';

/**
 * Maps record metadata to UI display status
 */
export function getDisplayStatus(record: Metadata, expiresIn?: number): DisplayStatus {
  // Handle expiring soon case
  if (expiresIn && expiresIn < 3600) {
    return 'expiring-soon';
  }

  // Map record states to display statuses
  switch (record.state) {
    case 'new':
    case 'shared':
      return 'active';
    case 'received':
      return 'received';
    case 'burned':
      return 'burned';
    case 'orphaned':
    case 'viewed':
      return 'destroyed';
    default:
      return 'secured';
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
