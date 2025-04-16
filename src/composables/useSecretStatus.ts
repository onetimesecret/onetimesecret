// src/composables/useSecretStatus.ts

import { ApplicationError } from '@/schemas';
// import { type Secret } from '@/schemas/models/secret';
import { useSecretStore } from '@/stores/secretStore';
import { useNotificationsStore } from '@/stores/notificationsStore';
import { storeToRefs } from 'pinia';
import { computed, ref } from 'vue';
import { AsyncHandlerOptions, useAsyncHandler } from './useAsyncHandler';
import { useI18n } from 'vue-i18n';

/**
 * Composable for managing secret status operations
 * Provides a unified interface for interacting with secret status
 */
export function useSecretStatus() {
  const { t } = useI18n();
  const store = useSecretStore();
  const notifications = useNotificationsStore();

  // Extract store refs
  const { status } = storeToRefs(store);

  // Local state
  const isLoading = ref(false);
  const error = ref<ApplicationError | null>(null);
  const currentKey = ref<string | null>(null);

  const defaultAsyncHandlerOptions: AsyncHandlerOptions = {
    notify: (message, severity) => notifications.show(message, severity),
    setLoading: (loading) => (isLoading.value = loading),
    onError: (err) => (error.value = err),
  };

  // Composable async handler
  const { wrap } = useAsyncHandler(defaultAsyncHandlerOptions);

  /**
   * Get the current status of a secret
   * @param secretKey - Unique identifier for the secret
   */
  const getStatus = async (secretKey: string) =>
    wrap(async () => {
      currentKey.value = secretKey;
      return await store.getStatus(secretKey);
    });

  /**
   * Check if a secret requires a passphrase
   */
  const requiresPassphrase = computed(() => status.value?.protected === true);

  /**
   * Check if a secret has been burned
   */
  const isBurned = computed(() => status.value?.burned === true);

  /**
   * Check if a secret has been viewed
   */
  const isViewed = computed(() => status.value?.viewed === true);

  /**
   * Get a user-friendly status message
   */
  const statusMessage = computed(() => {
    if (!status.value) return '';

    if (status.value.burned) {
      return t('web.private.burned');
    } else if (status.value.viewed) {
      return t('web.private.viewed');
    } else if (status.value.protected) {
      return t('web.private.requires_passphrase');
    } else {
      return t('web.private.created_success');
    }
  });

  /**
   * Reset the status state
   */
  const clearStatus = () => {
    error.value = null;
    isLoading.value = false;
    currentKey.value = null;
    store.status.value = null;
  };

  return {
    // State
    status,
    isLoading,
    error,
    currentKey,

    // Computed
    requiresPassphrase,
    isBurned,
    isViewed,
    statusMessage,

    // Actions
    getStatus,
    clearStatus,
  };
}
