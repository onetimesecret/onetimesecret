// composables/useMetadata.ts
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';

/**
 *
 */
export function useMetadata(metadataKey: string) {
  const router = useRouter();
  const notifications = useNotificationsStore();
  const store = useMetadataStore();

  // The `StoreGeneric` type assertion helps bridge the gap between the specific
  // store type and the generic store. This is a known issue when using
  // `storeToRefs` with stores that have complex types.
  const { record, details, isLoading, canBurn } = storeToRefs(store);

  // Local state
  const passphrase = ref('');

  const fetch = async () => {
    await store.fetch(metadataKey);
  };

  const handleBurn = async () => {
    if (!canBurn.value) {
      return;
    }

    await store.burn(metadataKey, passphrase.value);

    notifications.show('Secret burned successfully', 'success');
    await fetch();
    router.push({
      name: 'Metadata link',
      params: { metadataKey: metadataKey },
      query: { ts: Date.now().toString() },
    });
  };

  const reset = () => {
    // Reset local state
    passphrase.value = '';
    store.$reset();
  };

  return {
    // State
    record,
    details,
    isLoading,
    passphrase,

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
 * 1. Consider adding a `reset()` method to clear state
 * 2. Add proper typing for error states
 * 3. Consider adding validation for the passphrase before attempting to burn
 * 4. Add proper cleanup in case the component is unmounted during async operations
 */
