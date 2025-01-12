// src/utils/status.ts

import { type Metadata, MetadataState, isValidMetadataState } from '@/schemas/models';
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
  if (!record?.state || !isValidMetadataState(record.state)) {
    return 'processing';
  }

  // Handle orphaned state first
  if (record.state === MetadataState.ORPHANED) return 'destroyed';

  // Check expiration
  if (expiresIn !== undefined && expiresIn > 0 && expiresIn < 3600) {
    return 'expiring-soon';
  }

  // Map states to display status
  switch (record.state) {
    case MetadataState.NEW:
    case MetadataState.SHARED:
      return 'active';
    case MetadataState.RECEIVED:
      return 'received';
    case MetadataState.BURNED:
      return 'burned';
    case MetadataState.VIEWED:
      return 'destroyed';
    default:
      return 'processing';
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
