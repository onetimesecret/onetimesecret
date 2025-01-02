// stores/metadataListStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import type { MetadataRecords, MetadataRecordsDetails } from '@/schemas/api/endpoints';
import { responseSchemas } from '@/schemas/api/responses';
import { createApi } from '@/utils/api';
import { type AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { ref, type Ref } from 'vue';

/**
 * Store for managing metadata records and their related operations.
 * Handles fetching, caching, and state management of metadata listings.
 */
/* eslint-disable max-lines-per-function */
export const useMetadataListStore = defineStore('metadataList', () => {
  // State
  const _initialized = ref(false);
  const isLoading = ref(false);
  const records: Ref<MetadataRecords[] | null> = ref(null);
  const details: Ref<MetadataRecordsDetails | null> = ref(null);
  const count = ref<number | null>(null);

  // Internal references
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useErrorHandler> | null = null;

  // Getters
  const recordCount = () => count.value;
  const initialized = () => _initialized.value;

  // Actions
  function _ensureErrorHandler() {
    if (!_errorHandler) setupErrorHandler();
  }

  function setupErrorHandler(
    api: AxiosInstance = createApi(),
    options: ErrorHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useErrorHandler({
      setLoading: (loading: boolean) => {
        isLoading.value = loading;
      },
      notify: options.notify,
      log: options.log,
    });
  }

  async function fetchList() {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.get('/api/v2/private/recent');
      const validated = responseSchemas.metadataList.parse(response.data);

      records.value = validated.records ?? [];
      details.value = validated.details ?? {};
      count.value = validated.count ?? 0;

      return validated;
    });
  }

  async function refreshRecords(force = false) {
    if (!force && _initialized.value) return;

    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      await fetchList();
      _initialized.value = true;
    });
  }

  /**
   * Reset store state to initial values.
   * Implementation of $reset() for setup stores since it's not automatically available.
   */
  function $reset() {
    isLoading.value = false;
    records.value = null;
    details.value = null;
    _initialized.value = false;
    count.value = null;
    _api = null;
    _errorHandler = null;
  }

  return {
    // State
    isLoading,
    records,
    details,
    _initialized,
    count,

    // Getters
    recordCount,
    initialized,

    // Actions
    setupErrorHandler,
    fetchList,
    refreshRecords,
    $reset,
  };
});
