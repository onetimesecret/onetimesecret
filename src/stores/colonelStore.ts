// stores/colonelStore.ts

import { responseSchemas, type ColonelData } from '@/schemas/api';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';

/**
 * Type definition for ColonelStore.
 */
export type ColonelStore = {
  // State
  pageData: ColonelData | null;
  _initialized: boolean;

  // Actions
  fetch: () => Promise<ColonelData>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const pageData = ref<ColonelData | null>(null);
  const _initialized = ref(false);

  // Actions
  async function fetch() {
    const response = await $api.get('/api/v2/colonel/dashboard');
    const validated = responseSchemas.colonel.parse(response.data);
    // Access the record property which contains the ColonelData
    pageData.value = validated.record;
    return pageData.value;
  }

  function dispose() {
    pageData.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    pageData.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    pageData,

    // Actions
    fetch,
    dispose,
    $reset,
  };
});
