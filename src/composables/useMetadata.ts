// composables/useMetadata.ts
import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { useRouter } from 'vue-router';

export function useMetadata(key: string) {
  const store = useMetadataStore();
  const notifications = useNotificationsStore();
  const router = useRouter();
  const { currentRecord, currentDetails, isLoading, error } = storeToRefs(store);

  // Local state
  const passphrase = ref('');

  const fetch = async () => {
    await store.fetchOne(key);
  };

  const handleBurn = async () => {
    try {
      await store.burn(key, passphrase.value);
      notifications.show('Secret burned successfully', 'success');
      await fetch();
      router.push({
        name: 'Metadata link',
        params: { metadataKey: key },
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
