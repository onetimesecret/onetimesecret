// composables/useMetadata.ts
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';
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
  const { currentRecord, currentDetails, isLoading, error } = storeToRefs(store);

  // Local state
  const passphrase = ref('');

  const fetch = async () => {
    await store.fetchOne(metadataKey);
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

  return {
    // State
    record: currentRecord,
    details: currentDetails,
    isLoading,
    error,
    passphrase,

    // Computed
    canBurn: computed(() => store.canBurn),

    // Actions
    fetch,
    burn: handleBurn,
  };
}

/**
 * Suggestions:
 * 1. Consider adding a `reset()` method to clear state
 * 2. Add proper typing for error states
 * 3. Consider adding validation for the passphrase before attempting to burn
 * 4. Add proper cleanup in case the component is unmounted during async operations
 */
