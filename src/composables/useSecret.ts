// src/composables/useSecret.ts

import { useSecretStore } from '@/stores/secretStore';
import { storeToRefs } from 'pinia';
import { reactive } from 'vue';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

export function useSecret(secretIdentifier: string, options?: AsyncHandlerOptions) {
  const store = useSecretStore();
  const { record, details } = storeToRefs(store);

  const state = reactive({
    isLoading: false,
    error: '',
    success: '',
  });

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => {
      if (severity === 'error') {
        state.error = message;
      } else {
        state.success = message;
      }
    },
    setLoading: (loading) => (state.isLoading = loading),
    onError: () => (state.success = ''),
    ...options,
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const load = () =>
    wrap(async () => {
      await store.fetch(secretIdentifier);
    });

  const reveal = (passphrase: string) =>
    wrap(async () => {
      await store.reveal(secretIdentifier, passphrase);
    });

  return {
    // State
    state,
    record,
    details,

    // Actions
    load,
    reveal,
  };
}
