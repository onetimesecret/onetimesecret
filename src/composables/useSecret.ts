// src/composables/useSecret.ts

import { useAuthStore } from '@/stores/authStore';
import { useSecretStore } from '@/stores/secretStore';
import { storeToRefs } from 'pinia';
import { reactive } from 'vue';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Options for configuring secret composable behavior.
 */
export interface SecretOptions extends AsyncHandlerOptions {
  /** Force public API mode regardless of auth state */
  usePublicApi?: boolean;
}

/**
 * Composable for managing secret operations.
 * Automatically detects guest mode based on authentication state.
 *
 * @param secretKey - The unique identifier for the secret
 * @param options - Optional configuration for API mode and async handling
 */
export function useSecret(secretKey: string, options?: SecretOptions) {
  const authStore = useAuthStore();
  const store = useSecretStore();

  // Auto-detect guest mode based on auth state unless explicitly overridden
  const usePublicApi = options?.usePublicApi ?? !authStore.isAuthenticated;
  store.setApiMode(usePublicApi ? 'public' : 'authenticated');

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
      await store.fetch(secretKey);
    });

  const reveal = (passphrase: string) =>
    wrap(async () => {
      await store.reveal(secretKey, passphrase);
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
