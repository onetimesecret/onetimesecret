// src/shared/stores/incomingStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import {
  IncomingConfig,
  IncomingSecretPayload,
  IncomingSecretResponse,
  incomingConfigSchema,
  incomingSecretResponseSchema,
} from '@/schemas/api/incoming';
import { responseSchemas, ReceiptResponse } from '@/schemas/api/v3/responses';
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
  isLoading: boolean;
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
  loadConfig: () => Promise<IncomingConfig | undefined>;
  createIncomingSecret: (payload: IncomingSecretPayload) => Promise<IncomingSecretResponse>;
  getReceipt: (key: string) => Promise<ReceiptResponse>;
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
  const isLoading = ref(false);
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
   * @returns Validated incoming config response or undefined on error
   */
  const loadConfig = async () => {
    configError.value = null;
    const response = await $api.get('/api/v3/incoming/config');
    const validated = incomingConfigSchema.parse(response.data.config);
    config.value = validated;
    return validated;
  };

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

    const response = await $api.post('/api/v3/incoming/secret', {
      secret: payload,
    });

    const validated = incomingSecretResponseSchema.parse(response.data);
    return validated;
  }

  /**
   * Fetches a receipt by key from the public guest endpoint.
   * Used to check the status of an incoming secret after creation.
   *
   * @param key - Receipt identifier (extid)
   * @throws {ZodError} When response fails schema validation
   * @throws {AxiosError} When request fails (including 404 for unknown keys)
   * @returns Validated receipt response
   */
  async function getReceipt(key: string): Promise<ReceiptResponse> {
    const response = await $api.get(`/api/v3/guest/receipt/${key}`);
    return responseSchemas.receipt.parse(response.data);
  }

  function clear() {
    config.value = null;
    configError.value = null;
    isLoading.value = false;
  }

  /**
   * Resets the store state to its initial values
   */
  function $reset() {
    config.value = null;
    configError.value = null;
    isLoading.value = false;
    _initialized.value = false;
  }

  return {
    // State
    config,
    isLoading,
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
    getReceipt,
    clear,
    $reset,
  };
});
