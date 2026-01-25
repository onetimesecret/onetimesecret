// src/shared/composables/useReceipt.ts

import { ApplicationError } from '@/schemas';
import { useAuthStore } from '@/shared/stores/authStore';
import { useReceiptStore } from '@/shared/stores/receiptStore';
import { useNotificationsStore } from '@/shared/stores/notificationsStore';
import { NotificationSeverity } from '@/types/ui/notifications';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Options for the useReceipt composable.
 */
interface ReceiptOptions {
  /**
   * Force public API mode regardless of auth state.
   * When true, uses /api/v3/guest/receipt/* endpoints.
   * When false/undefined, auto-detects based on auth state.
   */
  usePublicApi?: boolean;
}

export function useReceipt(receiptIdentifier: string, options?: ReceiptOptions) {
  const router = useRouter();
  const notifications = useNotificationsStore();
  const store = useReceiptStore();
  const authStore = useAuthStore();

  // Set API mode based on auth state or explicit option
  // Uses public /guest endpoints for anonymous users
  const usePublicApi = options?.usePublicApi ?? !authStore.isAuthenticated;
  store.setApiMode(usePublicApi ? 'public' : 'authenticated');

  // Auto-detect guest mode based on auth state unless explicitly overridden
  const usePublicApi = options?.usePublicApi ?? !authStore.isAuthenticated;
  store.setApiMode(usePublicApi ? 'public' : 'authenticated');

  // The `StoreGeneric` type assertion helps bridge the gap between the specific
  // store type and the generic store. This is a known issue when using
  // `storeToRefs` with stores that have complex types.
  const { record, details, canBurn } = storeToRefs(store);

  // Local state
  const passphrase = ref('');
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  // const hasPassphrase = computed(
  //   // TODO: could be more consistent
  //   () => !details?.can_decrypt && !record?.is_received && !record?.is_destroyed
  // );

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity as NotificationSeverity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  // Composable async handler
  const { wrap, createError } = useAsyncHandler(defaultAsyncHandlerOptions);

  const fetch = async () =>
    wrap(async () => {
      const result = await store.fetch(receiptIdentifier);
      return result;
    });

  const burn = () =>
    wrap(async () => {
      if (!canBurn.value) {
        throw createError('Cannot burn this secret', 'human', 'error'); // fires synchronously fyi
      }

      await store.burn(receiptIdentifier, passphrase.value);

      // Should be handled by the async handler
      //notifications.show('Secret burned successfully', 'success');

      router.push({
        name: 'Receipt link',
        params: { receiptIdentifier },
        query: { ts: Date.now().toString() },
      });
    });

  const reset = () => {
    // Reset local state
    passphrase.value = '';
    error.value = null;
    isLoading.value = false;
    // Reset store state
    store.$reset();
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
    burn,
    reset,
  };
}


/**
 * Suggestions:
 * 1. Consider adding validation for the passphrase before attempting to burn
 * 2. Add proper cleanup in case the component is unmounted during async operations
 */
