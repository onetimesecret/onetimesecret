// stores/colonelStore.ts

import { responseSchemas, type ColonelDetails } from '@/schemas/api';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';

/**
 * Type definition for ColonelStore.
 */
export type ColonelStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: ColonelDetails;

  // Actions
  fetch: () => Promise<ColonelDetails>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<ColonelDetails | null>(null);
  const _initialized = ref(false);

  // Actions
  async function fetch() {
    const response = await $api.get('/api/v2/colonel');
    try {
      const validated = responseSchemas.colonel.parse(response.data);
      console.log('Colonel validation successful:', validated);
      details.value = validated.details;

      return record.value;
    } catch (error) {
      console.error('Colonel validation failed:', {
        error,
        data: response.data,
      });
      throw error;
    }
  }

  function dispose() {
    record.value = null;
    details.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    record,
    details,

    // Actions
    fetch,
    dispose,
    $reset,
  };
});
