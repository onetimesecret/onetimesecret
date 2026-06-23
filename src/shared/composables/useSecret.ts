// src/shared/composables/useSecret.ts

import { useAuthStore } from '@/shared/stores/authStore';
import { useSecretStore } from '@/shared/stores/secretStore';
import { storeToRefs } from 'pinia';
import { reactive } from 'vue';

import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';

/**
 * Options for the useSecret composable.
 */
interface SecretOptions extends AsyncHandlerOptions {
  /**
   * Force public API mode regardless of auth state.
   * When true, uses /api/v3/guest/secret/* endpoints.
   * When false/undefined, auto-detects based on auth state.
   */
  usePublicApi?: boolean;
}

export function useSecret(secretIdentifier: string, options?: SecretOptions) {
  const store = useSecretStore();
  const authStore = useAuthStore();
  const { record, details } = storeToRefs(store);

  // Set API mode based on auth state or explicit option
  // Uses public /guest endpoints for anonymous users
  const usePublicApi = options?.usePublicApi ?? !authStore.isAuthenticated;
  store.setApiMode(usePublicApi ? 'public' : 'authenticated');

  const state = reactive({
    isLoading: false,
    error: '',
    // HTTP status / error code of the last failure, so consumers can tell a
    // terminal "not found" (404 — consumed/expired) apart from a transient or
    // schema-parse failure. Without this, every error rendered as the misleading
    // "this secret has been viewed or expired" view (#3424).
    errorCode: null as string | number | null,
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
    onError: (err) => {
      state.success = '';
      state.errorCode = err.code ?? null;
    },
    ...options,
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const load = () =>
    wrap(async () => {
      state.error = '';
      state.errorCode = null;
      await store.fetch(secretIdentifier);
    });

  const reveal = (passphrase: string) =>
    wrap(async () => {
      state.error = '';
      state.errorCode = null;
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
