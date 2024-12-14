// New composable: src/composables/useMetadataBurn.ts

import { useMetadataStore } from '@/stores/metadataStore';
import { useNotificationsStore } from '@/stores/notifications';
import { ref } from 'vue';
import { useRouter } from 'vue-router';

export function useMetadataBurn(metadataKey: string) {
  const metadataStore = useMetadataStore();
  const notifications = useNotificationsStore();
  const router = useRouter();
  const passphrase = ref('');

  const handleBurn = async () => {
    try {
      const result = await metadataStore.burnMetadata(metadataKey, passphrase.value);
      notifications.show('Secret burned successfully', 'success');
      router.push({
        name: 'Metadata link',
        params: { metadataKey: result?.record.key },
      });
    } catch (error) {
      notifications.show(error instanceof Error ? error.message : 'Failed to burn secret', 'error');
      console.error('Error burning secret:', error);
    }
  };

  return {
    passphrase,
    handleBurn,
  };
}
