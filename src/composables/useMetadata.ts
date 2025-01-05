// composables/useMetadata.ts
import { ApplicationError } from '@/schemas';
import { loggingService } from '@/services/logging';
import { useMetadataStore } from '@/stores/metadataStore';
import { NotificationSeverity, useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';
import { useAsyncHandler } from './useAsyncHandler';

export const defaultAsyncHandlerOptions = {
  notify: (message: string, severity: string) =>
    loggingService.info(`[notify] ${severity}: ${message}`),
  log: (error: Error) => loggingService.error(error),
};

/**
 *
 */
/* eslint-disable max-lines-per-function */
export function useMetadata(metadataKey: string) {
  const router = useRouter();
  const notifications = useNotificationsStore();
  const store = useMetadataStore();

  // The `StoreGeneric` type assertion helps bridge the gap between the specific
  // store type and the generic store. This is a known issue when using
  // `storeToRefs` with stores that have complex types.
  const { record, details, canBurn } = storeToRefs(store);

  // Local state
  const passphrase = ref('');
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  const { wrap, createError } = useAsyncHandler({
    notify: (message, severity) =>
      notifications.show(message, severity as NotificationSeverity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  });

  const fetch = () =>
    wrap(async () => {
      const result = await store.fetch(metadataKey);
      return result;
    });

  const handleBurn = () =>
    wrap(async () => {
      if (!canBurn.value) {
        throw createError('Cannot burn this secret', 'human', 'error');
      }
      await store.burn(metadataKey, passphrase.value);
      notifications.show('Secret burned successfully', 'success');
      await fetch();
      router.push({
        name: 'Metadata link',
        params: { metadataKey },
        query: { ts: Date.now().toString() },
      });
    });

  const reset = () => {
    // Reset local state
    passphrase.value = '';
    store.$reset();
    isLoading.value = false;
    error.value = null;
  };

  return {
    // State
    record,
    details,
    isLoading,
    passphrase,
    error,

    // Computed
    canBurn: computed(() => store.canBurn),

    // Actions
    fetch,
    burn: handleBurn,
    reset,
  };
}

/**
 * Suggestions:
 * 1. Consider adding validation for the passphrase before attempting to burn
 * 2. Add proper cleanup in case the component is unmounted during async operations
 */
