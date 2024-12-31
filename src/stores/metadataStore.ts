// stores/metadataStore.ts
import {
  createError,
  ErrorHandlerOptions,
  useErrorHandler,
} from '@/composables/useErrorHandler';
import { responseSchemas } from '@/schemas/api/responses';
import { Metadata, MetadataDetails } from '@/schemas/models/metadata';
import { createApi } from '@/utils/api';
import { type AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { computed, ref } from 'vue';

export const METADATA_STATUS = {
  NEW: 'new',
  SHARED: 'shared',
  RECEIVED: 'received',
  BURNED: 'burned',
  VIEWED: 'viewed',
  ORPHANED: 'orphaned',
} as const;

/* eslint-disable max-lines-per-function */
export const useMetadataStore = defineStore('metadata', () => {
  // State
  const isLoading = ref(false);
  const record = ref<Metadata | null>(null);
  const details = ref<MetadataDetails | null>(null);

  // Private store utilities
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useErrorHandler> | null = null;

  // Getters
  const canBurn = computed((): boolean => {
    if (!record.value) {
      throw createError('No state metadata record', 'technical', 'error');
    }

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

  async function fetch(key: string) {
    _ensureErrorHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.get(`/api/v2/private/${key}`);
      const validated = responseSchemas.metadata.parse(response.data);
      record.value = validated.record;
      details.value = validated.details;
      return validated;
    });
  }

  async function burn(key: string, passphrase?: string) {
    _ensureErrorHandler();

    if (!canBurn.value) {
      throw createError('Cannot burn this metadata', 'human', 'error');
    }

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.post(`/api/v2/private/${key}/burn`, {
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
  function $reset() {
    isLoading.value = false;
    record.value = null;
    details.value = null;
    _api = null;
    _errorHandler = null;
  }

  return {
    // State
    isLoading,
    record,
    details,

    // Getters
    canBurn,

    // Actions
    setupErrorHandler,
    fetch,
    burn,
    $reset,
  };
});

export type MetadataStore = ReturnType<typeof useMetadataStore>;
