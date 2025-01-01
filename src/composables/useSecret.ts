// composables/useSecret.ts
import { useSecretsStore } from '@/stores/secretsStore';
import { storeToRefs } from 'pinia';
import { ref, type Ref } from 'vue';

export function useSecret(key: string) {
  const store = useSecretsStore();
  const { record, details, isLoading, error } = storeToRefs(store);

  // Local state
  const passphrase = ref('');

  const load = async () => {
    await store.fetch(key);
  };

  const reveal = async (passphrase: Ref) => {
    await store.reveal(key, passphrase.value);
  };

  return {
    // State
    record: record,
    details: details,
    isLoading,
    error,
    passphrase,

    // Computed
    // canBurn: computed(() => store.canBurn),

    // Actions
    load,
    reveal,
  };
}
