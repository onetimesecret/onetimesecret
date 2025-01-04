// stores/colonelStore.ts

import { AsyncHandlerOptions, useAsyncHandler } from '@/composables/useAsyncHandler';
import { responseSchemas, type ColonelData } from '@/schemas/api';
import { createApi } from '@/utils/api';
import { AxiosInstance } from 'axios';
import { defineStore } from 'pinia';
import { ref } from 'vue';

export const useColonelStore = defineStore('colonel', () => {
  // State
  const isLoading = ref(false);
  const pageData = ref<ColonelData | null>(null);
  const _initialized = ref(false);

  // Private store instance vars (closure based DI)
  let _api: AxiosInstance | null = null;
  let _errorHandler: ReturnType<typeof useAsyncHandler> | null = null;

  // Internal utilities
  function _ensureAsyncHandler() {
    if (!_errorHandler) setupAsyncHandler();
  }

  /**
   * Initialize error handling with optional custom API client and options
   */
  function setupAsyncHandler(
    api: AxiosInstance = createApi(),
    options: AsyncHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useAsyncHandler({
      setLoading: (loading) => (isLoading.value = loading),
      notify: options.notify,
      log: options.log,
    });
  }

  // Actions
  async function fetch() {
    _ensureAsyncHandler();

    return await _errorHandler!.withErrorHandling(async () => {
      const response = await _api!.get('/api/v2/colonel/dashboard');
      const validated = responseSchemas.colonel.parse(response.data);
      // Access the record property which contains the ColonelData
      pageData.value = validated.record;
      return pageData.value;
    });
  }

  function dispose() {
    pageData.value = null;
    isLoading.value = false;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    isLoading.value = false;
    pageData.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    isLoading,
    pageData,

    // Actions
    fetch,
    dispose,
    $reset,
  };
});
