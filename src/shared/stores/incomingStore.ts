// src/shared/stores/incomingStore.ts

import { PiniaPluginOptions } from '@/plugins/pinia';
import {
  IncomingConfig,
  IncomingSecretPayload,
  incomingConfigSchema,
} from '@/schemas/api/incoming';
import { ConcealDataResponse, MetadataResponse, responseSchemas } from '@/schemas/api/v3/responses';
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
  createIncomingSecret: (payload: IncomingSecretPayload) => Promise<ConcealDataResponse>;
  getReceipt: (identifier: string) => Promise<MetadataResponse>;
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
   * Creates a new incoming secret using the guest endpoint
   * @param payload - Validated incoming secret creation payload
   * @throws Will throw an error if the API call fails or validation fails
   * @returns Validated conceal data response with metadata and secret
   */
  async function createIncomingSecret(
    payload: IncomingSecretPayload
  ): Promise<ConcealDataResponse> {
    if (!config.value?.enabled) {
      throw new Error('Incoming secrets feature is not enabled');
    }

    const response = await $api.post('/api/v3/share/secret/conceal', {
      secret: payload,
    });

    const validated = responseSchemas.concealData.parse(response.data);
    return validated;
  }

  /**
   * Fetches the receipt/metadata for an incoming secret using the guest endpoint
   * @param identifier - The metadata identifier
   * @returns Validated metadata response
   */
  async function getReceipt(identifier: string): Promise<MetadataResponse> {
    const response = await $api.get(`/api/v3/share/receipt/${identifier}`);
    const validated = responseSchemas.metadata.parse(response.data);
    return validated;
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
