// composables/useSecret.ts
import { SecretStore, useSecretStore } from '@/stores/secretStore';
import { storeToRefs } from 'pinia';
import { ref } from 'vue';

export function useSecret(key: string) {
  const store = useSecretStore() as SecretStore;
  const { record, details, isLoading } = storeToRefs(store);

  // Local state
  const passphrase = ref('');

  const load = async () => {
    await store.fetch(key);
  };

  const reveal = async (passphrase: string) => {
    await store.reveal(key, passphrase);
  };

  return {
    // State
    record: record,
    details: details,
    isLoading,
    passphrase,

    // Computed
    // canBurn: computed(() => store.canBurn),

    // Actions
    load,
    reveal,
  };
}
