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
  config: Record<string, any> | null;

  // Actions
  fetch: () => Promise<ColonelDetails>;
  fetchConfig: () => Promise<Record<string, any>>;
  updateConfig: (config: Record<string, any>) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<ColonelDetails | null>(null);
  const config = ref<Record<string, any> | null>(null);
  const _initialized = ref(false);
  const isLoading = ref(false);

  // Actions
  async function fetch() {
    isLoading.value = true;
    let response;

    try {
      response = await $api.get('/api/v2/colonel');

      const validated = responseSchemas.colonel.parse(response.data);
      console.debug('Colonel validation successful:', validated);
      details.value = validated.details;

      // After fetching colonel data, also fetch the configuration
      await fetchConfig();

      return record.value;
    } catch (error) {
      console.error('Colonel validation failed:', {
        error,
        data: response?.data,
      });
      throw error;
    } finally {
      isLoading.value = false;
    }
  }

  async function fetchConfig() {
    try {
      const response = await $api.get('/api/v2/colonel/config');
      config.value = response.data;
      return config.value;
    } catch (error) {
      console.error('Failed to fetch configuration:', error);
      throw error;
    }
  }

  async function updateConfig(newConfig: Record<string, any>) {
    try {
      await $api.post('/api/v2/colonel/config', newConfig);
      config.value = newConfig;
    } catch (error) {
      console.error('Failed to update configuration:', error);
      throw error;
    }
  }

  function dispose() {
    record.value = null;
    details.value = null;
    config.value = null;
  }

  /**
   * Reset store state to initial values
   */
  function $reset() {
    record.value = null;
    details.value = null;
    config.value = null;
    _initialized.value = false;
  }

  // Expose store interface
  return {
    // State
    record,
    details,
    config,
    isLoading,

    // Actions
    fetch,
    fetchConfig,
    updateConfig,
    dispose,
    $reset,
  };
});
