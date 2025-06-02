// stores/colonelInfoStore.ts

import { responseSchemas, type ColonelInfoDetails } from '@/schemas/api';
import { type SystemSettingsDetails } from '@/schemas/api/endpoints/colonel';
import { AxiosInstance } from 'axios';
import { defineStore, PiniaCustomProperties } from 'pinia';
import { inject, ref } from 'vue';

/**
 * Type definition for ColonelInfoStore.
 */
export type ColonelInfoStore = {
  // State
  _initialized: boolean;
  record: {} | null; // response is empty object
  details: ColonelInfoDetails;
  config: SystemSettingsDetails | null;

  // Actions
  fetchInfo: () => Promise<ColonelInfoDetails>;
  fetchConfig: () => Promise<SystemSettingsDetails>;
  updateConfig: (config: SystemSettingsDetails) => Promise<void>;
  dispose: () => void;
  $reset: () => void;
} & PiniaCustomProperties;

export const useColonelInfoStore = defineStore('colonel', () => {
  const $api = inject('api') as AxiosInstance;

  // State
  const record = ref<{} | null>(null);
  const details = ref<ColonelInfoDetails | null>(null);
  const _initialized = ref(false);
  const isLoading = ref(false);

  // Actions
  async function fetch() {
    const response = await $api.get('/api/v2/colonel/info');
    const validated = responseSchemas.colonelInfo.parse(response.data);
    details.value = validated.details;
    return validated.record;
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
    isLoading,

    // Actions
    fetch,
    dispose,
    $reset,
  };
});
