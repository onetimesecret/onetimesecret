// composables/useMetadata.ts
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { StoreGeneric, storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';

/**
 *
 * @param key
 * @returns
 */
export function useMetadata(metadataKey: string) {
  const store = useMetadataStore();
  const notifications = useNotificationsStore();
  const router = useRouter();

  // The `StoreGeneric` type assertion helps bridge the gap between the specific
  // store type and the generic store. This is a known issue when using
  // `storeToRefs` with stores that have complex types.
  const { record, details, isLoading } = storeToRefs(store as StoreGeneric);

  // Local state
  const passphrase = ref('');

  const fetch = async () => {
    await store.fetch(metadataKey);
  };

  const handleBurn = async () => {
    try {
      await store.burn(metadataKey, passphrase.value);
      notifications.show('Secret burned successfully', 'success');
      await fetch();
      router.push({
        name: 'Metadata link',
        params: { metadataKey: metadataKey },
        query: { ts: Date.now().toString() },
      });
    } catch (error) {
      notifications.show(
        error instanceof Error ? error.message : 'Failed to burn secret',
        'error'
      );
      console.error('Error burning secret:', error);
    }
  };

  const reset = () => {
    // Reset local state
    passphrase.value = '';
    store.$reset();
  };

  return {
    // State
    record: record,
    details: details,
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
