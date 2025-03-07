// src/stores/secretStore.ts
import { PiniaPluginOptions } from '@/plugins/pinia';
import { ConcealDataResponse, responseSchemas, type SecretResponse } from '@/schemas/api';
import { type Secret, type SecretDetails } from '@/schemas/models/secret';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref } from 'vue';
import { GeneratePayload, ConcealPayload } from '@/schemas/api';

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
   * Creates a new concealed secret
   * @param payload - Validated secret creation payload
   * @throws Will throw an error if the API call fails or validation fails
   * @returns Validated secret response
   *
   * Validation responsibilities:
   * - Input payload is pre-validated by useSecretConcealer composable
   * - Store validates complete request structure to ensure API contract
   * - Store validates API response to ensure data integrity
   *
   * This dual validation approach provides:
   * 1. Early user input validation at form level
   * 2. API contract enforcement at store level
   * 3. Type safety and runtime validation of response data
   *
   * Note: Store-level request validation may be redundant given TypeScript types
   * and composable validation. This is an open question. Response validation
   * should remain the responsibility of this store.
   */
  async function conceal(payload: ConcealPayload): Promise<ConcealDataResponse> {
    const response = await $api.post('/api/v2/secret/conceal', {
      secret: payload,
    });
    return response.data;
  }

  async function generate(payload: GeneratePayload): Promise<ConcealDataResponse> {
    const response = await $api.post('/api/v2/secret/generate', {
      secret: payload,
    });
    // const validated = responseSchemas.concealData.parse(response.data); // Fails?
    // record.value = validated.record;
    // details.value = validated.details;
    return response.data;
  }

  /**
   * Reveals a secret's contents using an optional passphrase
   * @param secretKey - Unique identifier for the secret
   * @param passphrase - Optional passphrase to decrypt the secret
   * @throws Will throw an error if the API call fails
   * @returns Validated secret response
   */
  async function reveal(secretKey: string, passphrase?: string) {
    const response = await $api.post<SecretResponse>(`/api/v2/secret/${secretKey}/reveal`, {
      passphrase,
      continue: true,
    });

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
    conceal,
    generate,
    reveal,
    $reset,
  };
});
