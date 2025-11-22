// src/stores/incomingStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import {
  IncomingConfig,
  IncomingSecretPayload,
  IncomingSecretResponse,
  incomingConfigSchema,
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
  isConfigLoading: boolean;
  configError: string | null;
  _initialized: boolean;

  // Getters
  isInitialized: boolean;
  isFeatureEnabled: boolean;
  memoMaxLength: number;
  recipients: IncomingConfig['recipients'];
  defaultTtl: number | undefined;

  // Actions
  init: () => { isInitialized: boolean };
  loadConfig: () => Promise<IncomingConfig>;
  createIncomingSecret: (payload: IncomingSecretPayload) => Promise<IncomingSecretResponse>;
  clear: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

/**
 * Store for managing incoming secrets feature configuration and operations
 */
/* eslint-disable max-lines-per-function */
export const useIncomingStore = defineStore('incoming', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const config = ref<IncomingConfig | null>(null);
  const isConfigLoading = ref(false);
  const configError = ref<string | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);
  const isFeatureEnabled = computed(() => config.value?.enabled ?? false);
  const memoMaxLength = computed(() => config.value?.memo_max_length ?? 50);
  const recipients = computed(() => config.value?.recipients ?? []);
  const defaultTtl = computed(() => config.value?.default_ttl);

  // Actions

  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;

    return { isInitialized };
  }

  /**
   * Loads incoming secrets configuration from API
   * @throws Will throw an error if the API call fails or validation fails
   * @returns Validated incoming config response
   */
  async function loadConfig(): Promise<IncomingConfig> {
    isConfigLoading.value = true;
    configError.value = null;

    try {
      const response = await $api.get('/api/v2/incoming/config');
      const validated = incomingConfigSchema.parse(response.data.config);
      config.value = validated;
      return validated;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : 'Failed to load configuration';
      configError.value = errorMessage;
      if (error instanceof Error) {
        loggingService.error(error);
      } else {
        loggingService.error(new Error('Failed to load incoming config'));
      }
      throw error;
    } finally {
      isConfigLoading.value = false;
    }
  }

  /**
   * Creates a new incoming secret
   * @param payload - Validated incoming secret creation payload
   * @throws Will throw an error if the API call fails or validation fails
   * @returns Validated incoming secret response
   */
  async function createIncomingSecret(
    payload: IncomingSecretPayload
  ): Promise<IncomingSecretResponse> {
    if (!config.value?.enabled) {
      throw new Error('Incoming secrets feature is not enabled');
    }

    const response = await $api.post('/api/v2/incoming/secret', {
      secret: payload,
    });

    const validated = incomingSecretResponseSchema.parse(response.data);
    return validated;
  }

  function clear() {
    config.value = null;
    configError.value = null;
    isConfigLoading.value = false;
  }

  /**
   * Resets the store state to its initial values
   */
  function $reset() {
    config.value = null;
    configError.value = null;
    isConfigLoading.value = false;
    _initialized.value = false;
  }

  return {
    // State
    config,
    isConfigLoading,
    configError,
    _initialized,

    // Getters
    isInitialized,
    isFeatureEnabled,
    memoMaxLength,
    recipients,
    defaultTtl,

    // Actions
    init,
    loadConfig,
    createIncomingSecret,
    clear,
    $reset,
  };
});
