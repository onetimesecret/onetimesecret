// stores/colonelStore.ts

import { ErrorHandlerOptions, useErrorHandler } from '@/composables/useErrorHandler';
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
  let _errorHandler: ReturnType<typeof useErrorHandler> | null = null;

  // Internal utilities
  function _ensureErrorHandler() {
    if (!_errorHandler) setupErrorHandler();
  }

  /**
   * Initialize error handling with optional custom API client and options
   */
  function setupErrorHandler(
    api: AxiosInstance = createApi(),
    options: ErrorHandlerOptions = {}
  ) {
    _api = api;
    _errorHandler = useErrorHandler({
      setLoading: (loading) => (isLoading.value = loading),
      notify: options.notify,
      log: options.log,
    });
  }

  // Actions
  async function fetch() {
    _ensureErrorHandler();

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
