// src/stores/metadataListStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia';
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/account/endpoints/recent';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref, type Ref } from 'vue';

/**
 * Type definition for MetadataListStore.
 */
export type MetadataListStore = {
  // State
  _initialized: boolean;
  records: MetadataRecords[];
  details: MetadataRecordsDetails | null;
  count: number | null;

  // Getters
  recordCount: number;
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
  const $api = inject('api') as AxiosInstance;

  // State
  const _initialized = ref(false);
  const records: Ref<MetadataRecords[] | null> = ref(null);
  const details: Ref<MetadataRecordsDetails | null> = ref(null);
  const count = ref<number | null>(null);

  // Getters
  const initialized = () => _initialized.value;
  const recordCount = () => count.value ?? 0;

  interface StoreOptions extends PiniaPluginOptions {}

  function init(options?: StoreOptions) {
    if (_initialized.value) return { initialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;
    return { initialized };
  }

  async function fetchList() {
    const response = await $api.get('/api/v3/receipt/recent');
    const validated = responseSchemas.metadataList.parse(response.data);

    records.value = validated.records ?? [];
    details.value = (validated.details ?? {}) as any;
    count.value = validated.count ?? 0;

    return validated;
  }

  async function refreshRecords(force = false) {
    if (!force && _initialized.value) return;

    await fetchList();
    _initialized.value = true;
  }

  /**
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   */
  function $reset() {
    records.value = null;
    details.value = null;
    count.value = null;
    _initialized.value = false;
  }

  return {
    init,

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
