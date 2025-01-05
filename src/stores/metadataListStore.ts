// stores/metadataListStore.ts
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { responseSchemas } from '@/schemas/api/responses';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { ref, type Ref } from 'vue';

/**
 * Type definition for MetadataListStore.
 */
export type MetadataListStore = {
  // State
  _initialized: boolean;
  records: MetadataRecords[] | null;
  details: MetadataRecordsDetails | null;
  count: number | null;

  // Getters
  recordCount: number | null;
  initialized: boolean;

  // Actions
  fetchList: () => Promise<void>;
  refreshRecords: (force?: boolean) => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing metadata records and their related operations.
 * Handles fetching, caching, and state management of metadata listings.
 */
/* eslint-disable max-lines-per-function */
export const useMetadataListStore = defineStore('metadataList', () => {
  // State
  const _initialized = ref(false);
  const records: Ref<MetadataRecords[] | null> = ref(null);
  const details: Ref<MetadataRecordsDetails | null> = ref(null);
  const count = ref<number | null>(null);

  // Getters
  const recordCount = () => count.value ?? 0;
  const initialized = () => _initialized.value;

  async function fetchList(this: MetadataListStore) {
    const response = await this.$api.get('/api/v2/private/recent');
    const validated = responseSchemas.metadataList.parse(response.data);

    records.value = validated.records ?? [];
    details.value = validated.details ?? {};
    count.value = validated.count ?? 0;

    return validated;
  }

  async function refreshRecords(this: MetadataListStore, force = false) {
    if (!force && _initialized.value) return;

    await this.fetchList();
    _initialized.value = true;
  }

  /**
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   */
  function $reset(this: MetadataListStore) {
    records.value = null;
    details.value = null;
    _initialized.value = false;
    count.value = null;
  }

  return {
    // State
    records,
    details,
    count,

    // Getters
    recordCount,
    initialized,

    // Actions
    fetchList,
    refreshRecords,
    $reset,
  };
});
