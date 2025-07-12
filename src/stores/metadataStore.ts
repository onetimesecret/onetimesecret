// stores/metadataStore.ts
import { createError } from '@/composables/useAsyncHandler';
import { PiniaPluginOptions } from '@/plugins/pinia';
import { responseSchemas } from '@/schemas/api/responses';
import { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { loggingService } from '@/services/logging.service';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, inject, ref } from 'vue';

export const METADATA_STATUS = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  ORPHANED: 'orphaned',
} as const;

interface StoreOptions extends PiniaPluginOptions {}

/**
 * Type definition for MetadataStore.
 */
export type MetadataStore = {
  // State
  record: Metadata | null;
  details: MetadataDetails | null;
  _initialized: boolean;

  // Getters
  isInitialized: boolean;
  canBurn: boolean;

  // Actions
  init: () => { isInitialized: boolean };
  fetch: (key: string) => Promise<void>;
  burn: (key: string, passphrase?: string) => Promise<void>;
  $reset: () => void;
} & PiniaCustomProperties;

/* eslint-disable max-lines-per-function */
export const useMetadataStore = defineStore('metadata', () => {
  const $api = inject('api') as AxiosInstance;
  // State
  const record = ref<Metadata | null>(null);
  const details = ref<MetadataDetails | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);

  /**
   * Initializes the metadata store.
   * Idempotent - subsequent calls have no effect if already initialized.
   *
   * @returns Object containing initialization status
   */
  function init(options?: StoreOptions) {
    if (_initialized.value) return { isInitialized };

    if (options?.api) loggingService.warn('API instance provided in options, ignoring.');

    _initialized.value = true;
    return { isInitialized };
  }

  const canBurn = computed((): boolean => {
    if (!record.value) return false;

    const validStates = [
      METADATA_STATUS.NEW,
      METADATA_STATUS.SHARED,
      METADATA_STATUS.VIEWED,
    ] as const;

    if (
      record.value.burned ||
      !validStates.includes(record.value.state as (typeof validStates)[number])
    ) {
      return false;
    }

    return true;
  });

  /**
   * Fetches metadata for given key from API.
   * Validates response against metadata schema using Zod.
   * Updates store state with validated response.
   *
   * @param key - Metadata identifier
   * @throws {ZodError} When response fails schema validation
   * @throws {AxiosError} When request fails
   */
  async function fetch(key: string) {
    const response = await $api.get(`/api/v2/receipt/${key}`);
    const validated = responseSchemas.metadata.parse(response.data);
    record.value = validated.record;
    details.value = validated.details;
    return validated;
  }

  /**
   * Burns (destroys) metadata identified by key.
   * Validates current state allows burning via canBurn.
   * Updates store state with validated response.
   *
   * @param key - Metadata identifier
   * @param passphrase - Optional passphrase required for some secrets
   * @throws {ApplicationError} When metadata cannot be burned
   * @throws {ZodError} When response fails schema validation
   * @throws {AxiosError} When request fails
   */
  async function burn(key: string, passphrase?: string) {
    if (!canBurn.value) {
      throw createError('Cannot burn this metadata', 'human', 'error');
    }

    const response = await $api.post(`/api/v2/receipt/${key}/burn`, {
      passphrase,
      continue: true,
    });

    const validated = responseSchemas.metadata.parse(response.data);
    record.value = validated.record;
    details.value = validated.details;

    return validated;
  }

  /**
   * Resets store state to initial values.
   * Clears record, details and initialization status.
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

    // Getters
    canBurn,

    // Actions
    init,
    fetch,
    burn,
    $reset,
  };
});
