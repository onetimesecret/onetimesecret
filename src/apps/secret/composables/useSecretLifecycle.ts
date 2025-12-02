// src/apps/secret/composables/useSecretLifecycle.ts

import { ref, computed } from 'vue';
import { useSecretStore } from '@/shared/stores/secretStore';

export type SecretState =
  | 'idle'
  | 'loading'
  | 'passphrase'
  | 'ready'
  | 'revealed'
  | 'burned'
  | 'expired'
  | 'unknown';

export function useSecretLifecycle(secretKey: string) {
  const secretStore = useSecretStore();
  const state = ref<SecretState>('idle');
  const payload = ref<string | null>(null);
  const error = ref<Error | null>(null);

  const isTerminal = computed(() =>
    ['burned', 'expired', 'unknown'].includes(state.value)
  );

  const canReveal = computed(() =>
    ['ready', 'passphrase'].includes(state.value)
  );

  async function load() {
    state.value = 'loading';
    error.value = null;

    try {
      const data = await secretStore.fetch(secretKey);

      if (!data?.record) {
        state.value = 'unknown';
        return;
      }

      const record = data.record;
      if (record.state === 'burned') {
        state.value = 'burned';
      } else if (record.state === 'viewed') {
        state.value = 'revealed';
      } else if (record.has_passphrase) {
        state.value = 'passphrase';
      } else {
        state.value = 'ready';
      }
    } catch (e) {
      error.value = e as Error;
      state.value = 'unknown';
    }
  }

  async function reveal(passphrase?: string) {
    if (!canReveal.value) return;

    try {
      await secretStore.reveal(secretKey, passphrase);
      payload.value = secretStore.record?.secret_value ?? null;
      state.value = 'revealed';
    } catch (e) {
      error.value = e as Error;
      // Stay in current state on error
    }
  }

  return {
    state,
    payload,
    error,
    isTerminal,
    canReveal,
    load,
    reveal,
  };
}
