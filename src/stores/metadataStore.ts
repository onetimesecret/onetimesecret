// stores/metadataStore.ts
import { createError } from '@/composables/useAsyncHandler';
import { responseSchemas } from '@/schemas/api/responses';
import { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { computed, ref } from 'vue';

export const METADATA_STATUS = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  ORPHANED: 'orphaned',
} as const;

/**
 * Type definition for MetadataStore.
 */
export type MetadataStore = {
  // State
  isLoading: boolean;
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
  // State
  const isLoading = ref(false);
  const record = ref<Metadata | null>(null);
  const details = ref<MetadataDetails | null>(null);
  const _initialized = ref(false);

  // Getters
  const isInitialized = computed(() => _initialized.value);

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

  // Actions
  function init(this: MetadataStore) {
    if (_initialized.value) return { isInitialized };

    _initialized.value = true;

    return { isInitialized };
  }

  async function fetch(this: MetadataStore, key: string) {
    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.get(`/api/v2/private/${key}`);
      const validated = responseSchemas.metadata.parse(response.data);
      record.value = validated.record;
      details.value = validated.details;
      return validated;
    });
  }

  async function burn(this: MetadataStore, key: string, passphrase?: string) {
    if (!canBurn.value) {
      throw createError('Cannot burn this metadata', 'human', 'error');
    }

    return await this.$asyncHandler.wrap(async () => {
      const response = await this.$api.post(`/api/v2/private/${key}/burn`, {
        passphrase,
        continue: true,
      });
      const validated = responseSchemas.metadata.parse(response.data);
      record.value = validated.record;
      details.value = validated.details;
      return validated;
    });
  }

  // Implement $reset for setup store
  function $reset(this: MetadataStore) {
    isLoading.value = false;
    record.value = null;
    details.value = null;
    _initialized.value = false;
  }

  return {
    // State
    isLoading,
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
