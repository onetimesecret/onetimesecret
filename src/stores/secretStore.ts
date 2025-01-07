// src/stores/secretStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia';
import { responseSchemas, type SecretResponse } from '@/schemas/api';
import { type Secret, type SecretDetails } from '@/schemas/models/secret';
import { loggingService } from '@/services/logging';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref } from 'vue';

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for SecretStore.
 */
export type SecretStore = {
  // State
  record: Secret | null;
  details: SecretDetails | null;
  _initialized: boolean;

  // Getters
  isInitialized: boolean;

  // Actions
  init: () => { isInitialized: boolean };
  fetch: (secretKey: string) => Promise<void>;
  reveal: (secretKey: string, passphrase?: string) => Promise<void>;
  clear: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing secret records and their details
 */
/* eslint-disable max-lines-per-function */
export const useSecretStore = defineStore('secrets', () => {
  const $api = inject('api') as AxiosInstance;
  // State
  const record = ref<Secret | null>(null);
  const details = ref<SecretDetails | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);

  // Actions

  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;

    return { isInitialized };
  }

  /**
   * Loads a secret by its key
   * @param secretKey - Unique identifier for the secret
   * @throws Will throw an error if the API call fails
   * @returns Validated secret response
   */
  async function fetch(secretKey: string) {
    const response = await $api.get(`/api/v2/secret/${secretKey}`);
    const validated = responseSchemas.secret.parse(response.data);
    record.value = validated.record;
    details.value = validated.details;

    return validated;
  }

  /**
   * Reveals a secret's contents using an optional passphrase
   * @param secretKey - Unique identifier for the secret
   * @param passphrase - Optional passphrase to decrypt the secret
   * @throws Will throw an error if the API call fails
   * @returns Validated secret response
   */
  async function reveal(secretKey: string, passphrase?: string) {
    const response = await $api.post<SecretResponse>(
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
  }

  function clear() {
    record.value = null;
    details.value = null;
  }

  /**
   * Resets the store state to its initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
    _initialized.value = false;
  }

  return {
    // State
    record,
    details,

    // Actions
    init,
    clear,
    fetch,
    reveal,
    $reset,
  };
});
