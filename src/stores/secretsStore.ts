// src/stores/secretsStore.ts
import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
import { responseSchemas, type SecretResponse } from '@/schemas/api';
import { type Secret, type SecretDetails } from '@/schemas/models/secret';
import api, { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

/**
 * Store for managing secret records and their details
 */

/* eslint-disable max-lines-per-function */
export const useSecretsStore = defineStore('secrets', () => {
  // State
  const isLoading = ref(false);
  const record = ref<Secret | null>(null);
  const details = ref<SecretDetails | null>(null);
  const _initialized = ref(false);

  // Private properties
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useErrorHandler> | null = null;

  // Getters
  const isInitialized = computed(() => _initialized.value);

  // Actions
  function init(api?: AxiosInstance) {
    if (_initialized.value) return { isInitialized };

    _initialized.value = true;
    setupErrorHandler(api);

    return { isInitialized };
  }

  function _ensureErrorHandler() {
    if (!_errorHandler) setupErrorHandler();
  }

  function setupErrorHandler(
    api: AxiosInstance = createApi(),
    options: ErrorHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useErrorHandler({
      setLoading: (loading) => {
        isLoading.value = loading;
      },
      notify: options.notify,
      log: options.log,
    });
  }

  /**
   * Loads a secret by its key
   * @param secretKey - Unique identifier for the secret
   * @throws Will throw an error if the API call fails
   * @returns Validated secret response
   */
  async function fetch(secretKey: string) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.get(`/api/v2/secret/${secretKey}`);
      const validated = responseSchemas.secret.parse(response.data);
      record.value = validated.record;
      details.value = validated.details;

      return validated;
    });
  }

  /**
   * Reveals a secret's contents using an optional passphrase
   * @param secretKey - Unique identifier for the secret
   * @param passphrase - Optional passphrase to decrypt the secret
   * @throws Will throw an error if the API call fails
   * @returns Validated secret response
   */
  async function reveal(secretKey: string, passphrase?: string) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await api.post<SecretResponse>(
        `/api/v2/secret/${secretKey}/reveal`,
        {
          passphrase,
          continue: true,
        }
      );

      const validated = responseSchemas.secret.parse(response.data);
      record.value = validated.record;
      details.value = validated.details;

      return validated;
    });
  }

  /**
   * Resets the store state to its initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
  }

  return {
    // State
    isLoading,
    record,
    details,

    // Actions
    init,
    fetch,
    reveal,
    $reset,
  };
});
