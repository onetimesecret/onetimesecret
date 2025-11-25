// src/stores/incomingStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import {
  type IncomingConfig,
  type IncomingRecipient,
  type IncomingSecretPayload,
  type IncomingSecretResponse,
  incomingConfigResponseSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref } from 'vue';

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for IncomingStore.
 */
export type IncomingStore = {
  // State
  config: IncomingConfig | null;
  recipients: IncomingRecipient[];
  isLoading: boolean;
  error: string | null;
  lastResponse: IncomingSecretResponse | null;
  _initialized: boolean;

  // Getters
  isInitialized: boolean;
  isEnabled: boolean;
  memoMaxLength: number;

  // Actions
  init: () => { isInitialized: boolean };
  fetchConfig: () => Promise<IncomingConfig>;
  createSecret: (payload: IncomingSecretPayload) => Promise<IncomingSecretResponse>;
  validateRecipient: (recipientHash: string) => Promise<boolean>;
  clear: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing incoming secrets feature
 *
 * The incoming secrets feature allows anonymous users to send encrypted
 * secrets to pre-configured recipients via a web form.
 */
// eslint-disable-next-line max-lines-per-function -- Pinia setup store pattern requires single function
export const useIncomingStore = defineStore('incoming', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const config = ref<IncomingConfig | null>(null);
  const recipients = ref<IncomingRecipient[]>([]);
  const isLoading = ref(false);
  const error = ref<string | null>(null);
  const lastResponse = ref<IncomingSecretResponse | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const isEnabled = computed(() => config.value?.enabled ?? false);
  const memoMaxLength = computed(() => config.value?.memo_max_length ?? 50);

  // Actions

  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;

    return { isInitialized };
  }

  /**
   * Fetches the incoming secrets configuration from the API
   * @throws Will throw an error if the API call fails
   * @returns The incoming configuration
   */
  async function fetchConfig(): Promise<IncomingConfig> {
    isLoading.value = true;
    error.value = null;

    try {
      const response = await $api.get('/api/v3/incoming/config');
      const validated = incomingConfigResponseSchema.parse(response.data);

      config.value = validated.config;
      recipients.value = validated.config.recipients;

      return validated.config;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to load configuration';
      error.value = message;
      throw err;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Creates a new incoming secret
   * @param payload - The secret creation payload
   * @throws Will throw an error if the API call fails
   * @returns The created secret response
   */
  async function createSecret(payload: IncomingSecretPayload): Promise<IncomingSecretResponse> {
    isLoading.value = true;
    error.value = null;

    try {
      const response = await $api.post('/api/v3/incoming/secret', {
        secret: payload,
      });

      const validated = incomingSecretResponseSchema.parse(response.data);
      lastResponse.value = validated;

      return validated;
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Failed to create secret';
      error.value = message;
      throw err;
    } finally {
      isLoading.value = false;
    }
  }

  /**
   * Validates that a recipient hash exists in the configured recipients
   * @param recipientHash - The hash of the recipient to validate
   * @returns true if the recipient is valid
   */
  async function validateRecipient(recipientHash: string): Promise<boolean> {
    try {
      const response = await $api.post('/api/v3/incoming/validate', {
        recipient: recipientHash,
      });

      return response.data?.valid === true;
    } catch {
      return false;
    }
  }

  function clear() {
    lastResponse.value = null;
    error.value = null;
  }

  /**
   * Resets the store state to its initial values
   */
  function $reset() {
    config.value = null;
    recipients.value = [];
    isLoading.value = false;
    error.value = null;
    lastResponse.value = null;
    _initialized.value = false;
  }

  return {
    // State
    config,
    recipients,
    isLoading,
    error,
    lastResponse,
    _initialized,

    // Getters
    isInitialized,
    isEnabled,
    memoMaxLength,

    // Actions
    init,
    fetchConfig,
    createSecret,
    validateRecipient,
    clear,
    $reset,
  };
});
