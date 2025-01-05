// src/composables/useMetadataList.ts

import { ApplicationError } from '@/schemas';
import { useMetadataListStore } from '@/stores/metadataListStore';
import { NotificationSeverity, useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { ref } from 'vue';
import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Composable for managing metadata list operations
 * Provides a unified interface for interacting with metadata list store
 */
export function useMetadataList() {
  const store = useMetadataListStore();
  const notifications = useNotificationsStore();

  // Extract store refs
  const { records, details, count, recordCount } = storeToRefs(store);

  // Local state
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) =>
      notifications.show(message, severity as NotificationSeverity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  // Composable async handler
  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  /**
   * Fetch metadata list
   * @param force - Force refresh even if already initialized
   */
  const fetch = async () => wrap(async () => await store.fetchList());

  /**
   * Refresh metadata records
   * @param force - Force refresh regardless of initialization status
   */
  const refreshRecords = (force = false) =>
    wrap(async () => {
      await store.refreshRecords(force);
    });

  /**
   * Reset the metadata list store
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
