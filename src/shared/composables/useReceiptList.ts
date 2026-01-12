// src/shared/composables/useReceiptList.ts

import { ApplicationError } from '@/schemas';
import { useReceiptListStore } from '@/shared/stores/receiptListStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Composable for managing receipt list operations
 * Provides a unified interface for interacting with receipt list store
 */
export function useReceiptList() {
  const store = useReceiptListStore();
  const notifications = useNotificationsStore();

  // Extract store refs
  const { records, details, count } = storeToRefs(store);

  // Access recordCount directly from store
  const recordCount = computed(() => store.recordCount());

  // Local state
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  // Composable async handler
  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  /**
   * Fetch receipt list
   */
  const fetch = async () => wrap(async () => await store.fetchList());

  /**
   * Refresh receipt records
   * @param force - Force refresh regardless of initialization status
   */
  const refreshRecords = (force = false) =>
    wrap(async () => {
      await store.refreshRecords(force);
    });

  /**
   * Reset the receipt list store
   */
  const reset = () => {
    // Reset local state
    error.value = null;
    isLoading.value = false;

    // Reset store state
    store.$reset();
  };

  return {
    // State
    records,
    details,
    count,
    isLoading,
    error,

    // Computed
    recordCount,

    // Actions
    fetch,
    refreshRecords,
    reset,
  };
}

// Legacy alias for backward compatibility during migration
// TODO: Remove after all consumers have been updated
export const useMetadataList = useReceiptList;
