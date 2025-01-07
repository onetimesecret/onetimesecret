// src/composables/useSecret.ts

import { ApplicationError } from '@/schemas/errors/types';
import { useSecretStore } from '@/stores/secretStore';
import { storeToRefs } from 'pinia';
import { ref } from 'vue';

export function useSecret(key: string) {
  const store = useSecretStore();
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);
  const { record, details } = storeToRefs(store);

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
    error,
    passphrase,

    // Computed
    // canBurn: computed(() => store.canBurn),

    // Actions
    load,
    reveal,
  };
}
