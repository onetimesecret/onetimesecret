// src/composables/useSecret.ts

import { useSecretStore } from '@/stores/secretStore';
import { storeToRefs } from 'pinia';
import { reactive, ref } from 'vue';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { NotificationSeverity } from '@/types/ui/notifications';
import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';
import { ApplicationError } from '@/schemas/errors';

export function useSecret(secretKey: string) {
  const store = useSecretStore();
  const { record, details } = storeToRefs(store);

  const state = reactive({
    isLoading: false,
    error: '',
    success: '',
    passphrase: '',
  });

  const notifications = useNotificationsStore();
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) =>
      notifications.show(message, severity as NotificationSeverity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  const load = () =>
    wrap(async () => {
      await store.fetch(secretKey);
    });

  const reveal = (passphrase: string) =>
    wrap(async () => {
      await store.reveal(secretKey, passphrase);
      state.passphrase = '';
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
