// src/shared/stores/receiptListStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import type { ReceiptRecords, ReceiptRecordsDetails } from '@/schemas/api/account/endpoints/recent';
import { responseSchemas } from '@/schemas/api/v3/responses';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref, type Ref } from 'vue';

/**
 * Type definition for ReceiptListStore.
 */
export type ReceiptListStore = {
  // State
  _initialized: boolean;
  records: ReceiptRecords[];
  details: ReceiptRecordsDetails | null;
  count: number | null;

  // Getters
  recordCount: number;
  initialized: boolean;

  // Actions
  fetchList: () => Promise<void>;
  refreshRecords: (force?: boolean) => Promise<void>;
  updateMemo: (id: string, memo: string) => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing receipt records and their related operations.
 * Handles fetching, caching, and state management of receipt listings.
 */

// eslint-disable-next-line max-lines-per-function -- temporary debug logging
export const useReceiptListStore = defineStore('receiptList', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const _initialized = ref(false);
  const records: Ref<ReceiptRecords[] | null> = ref(null);
  const details: Ref<ReceiptRecordsDetails | null> = ref(null);
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

  // eslint-disable-next-line complexity -- temporary debug logging
  async function fetchList() {
    const timestamp = Date.now();
    loggingService.debug('[DEBUG:receiptListStore] fetchList called', {
      timestamp,
      currentCount: count.value,
      currentRecordsLength: records.value?.length ?? 0,
    });

    const response = await $api.get('/api/v3/receipt/recent');

    loggingService.debug('[DEBUG:receiptListStore] API response received', {
      timestamp,
      responseCount: response.data?.count,
      responseRecordsLength: response.data?.records?.length ?? 0,
      firstThreeIds: response.data?.records?.slice(0, 3).map((r: ReceiptRecords) => r.shortid),
    });

    const validated = responseSchemas.receiptList.parse(response.data);

    records.value = validated.records ?? [];
    details.value = (validated.details ?? {}) as any;
    count.value = validated.count ?? 0;

    loggingService.debug('[DEBUG:receiptListStore] Store updated', {
      timestamp,
      newCount: count.value,
      newRecordsLength: records.value?.length ?? 0,
    });

    return validated;
  }

  async function refreshRecords(force = false) {
    if (!force && _initialized.value) return;

    await fetchList();
    _initialized.value = true;
  }

  async function updateMemo(id: string, memo: string) {
    const response = await $api.patch(`/api/v3/receipt/${id}`, { memo });

    // Update the local record with the response from the API
    if (records.value && response.data?.record) {
      const updatedRecord = response.data.record;
      const index = records.value.findIndex((r) =>
        r.identifier === updatedRecord.identifier ||
        r.key === updatedRecord.key
      );

      if (index !== -1) {
        // Update just the memo field to preserve reactivity
        records.value[index].memo = updatedRecord.memo;
      }
    }

    return response.data;
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
    updateMemo,
    $reset,
  };
});
